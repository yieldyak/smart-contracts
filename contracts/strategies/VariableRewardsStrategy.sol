// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

import "../YakStrategyV2.sol";
import "../interfaces/IPair.sol";
import "../lib/DexLibrary.sol";
import "../lib/SafeERC20.sol";

/**
 * @notice VariableRewardsStrategy
 */
abstract contract VariableRewardsStrategy is YakStrategyV2 {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IWAVAX internal constant WAVAX = IWAVAX(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);

    struct Reward {
        address reward;
        uint256 amount;
    }

    struct RewardSwapPairs {
        address reward;
        address swapPair;
    }

    struct StrategySettings {
        uint256 minTokensToReinvest;
        uint256 adminFeeBips;
        uint256 devFeeBips;
        uint256 reinvestRewardBips;
    }

    // reward -> swapPair
    mapping(address => address) public rewardSwapPairs;
    uint256 public rewardCount = 1;

    constructor(
        string memory _name,
        address _depositToken,
        RewardSwapPairs[] memory _rewardSwapPairs,
        address _timelock,
        StrategySettings memory _strategySettings
    ) Ownable() {
        name = _name;
        depositToken = IERC20(_depositToken);
        rewardToken = IERC20(address(WAVAX));
        devAddr = 0x2D580F9CF2fB2D09BC411532988F2aFdA4E7BefF;

        for (uint256 i = 0; i < _rewardSwapPairs.length; i++) {
            _addReward(_rewardSwapPairs[i].reward, _rewardSwapPairs[i].swapPair);
        }

        updateMinTokensToReinvest(_strategySettings.minTokensToReinvest);
        updateAdminFee(_strategySettings.adminFeeBips);
        updateDevFee(_strategySettings.devFeeBips);
        updateReinvestReward(_strategySettings.reinvestRewardBips);
        updateDepositsEnabled(true);
        transferOwnership(_timelock);
        emit Reinvest(0, 0);
    }

    function addReward(address _rewardToken, address _swapPair) public onlyDev {
        _addReward(_rewardToken, _swapPair);
    }

    function _addReward(address _rewardToken, address _swapPair) internal {
        if (_rewardToken != address(rewardToken)) {
            require(
                DexLibrary.checkSwapPairCompatibility(IPair(_swapPair), _rewardToken, address(rewardToken)),
                "VariableRewardsStrategy::Swap pair does not contain reward token"
            );
        }
        rewardSwapPairs[_rewardToken] = _swapPair;
        rewardCount = rewardCount.add(1);
    }

    function removeReward(address rewardToken) public onlyDev {
        delete rewardSwapPairs[rewardToken];
        rewardCount = rewardCount.sub(1);
    }

    /**
     * @notice Approve tokens for use in Strategy
     * @dev Deprecated; approvals should be handled in context of staking
     */
    function setAllowances() public override onlyOwner {
        revert("setAllowances::deprecated");
    }

    /**
     * @notice Deposit tokens to receive receipt tokens
     * @param amount Amount of tokens to deposit
     */
    function deposit(uint256 amount) external override {
        _deposit(msg.sender, amount);
    }

    /**
     * @notice Deposit using Permit
     * @param amount Amount of tokens to deposit
     * @param deadline The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function depositWithPermit(
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {
        depositToken.permit(msg.sender, address(this), amount, deadline, v, r, s);
        _deposit(msg.sender, amount);
    }

    function depositFor(address account, uint256 amount) external override {
        _deposit(account, amount);
    }

    function _deposit(address account, uint256 amount) internal {
        require(DEPOSITS_ENABLED == true, "VariableRewardsStrategy::Deposits disabled");
        if (MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST > 0) {
            (Reward[] memory rewards, uint256 estimatedTotalReward) = _checkReward();
            if (estimatedTotalReward > MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST) {
                _reinvest(rewards);
            }
        }
        require(
            depositToken.transferFrom(msg.sender, address(this), amount),
            "VariableRewardsStrategy::Deposit token transfer failed"
        );
        uint256 depositFee = _calculateDepositFee(amount);
        _mint(account, getSharesForDepositTokens(amount.sub(depositFee)));
        _stakeDepositTokens(amount);
        emit Deposit(account, amount);
    }

    function _getDepositFeeBips() internal view virtual returns (uint256) {
        return 0;
    }

    function _calculateDepositFee(uint256 amount) internal view virtual returns (uint256) {
        uint256 depositFeeBips = _getDepositFeeBips();
        return amount.mul(depositFeeBips).div(_bip());
    }

    function withdraw(uint256 amount) external override {
        uint256 depositTokenAmount = getDepositTokensForShares(amount);
        require(depositTokenAmount > 0, "VariableRewardsStrategy::Withdraw amount too low");
        uint256 withdrawAmount = _withdrawFromStakingContract(amount);
        uint256 withdrawFee = _calculateWithdrawFee(depositTokenAmount);
        depositToken.safeTransfer(msg.sender, withdrawAmount.sub(withdrawFee));
        _burn(msg.sender, amount);
        emit Withdraw(msg.sender, depositTokenAmount);
    }

    function _getWithdrawFeeBips() internal view virtual returns (uint256) {
        return 0;
    }

    function _calculateWithdrawFee(uint256 amount) internal view virtual returns (uint256) {
        uint256 withdrawFeeBips = _getWithdrawFeeBips();
        return amount.mul(withdrawFeeBips).div(_bip());
    }

    function reinvest() external override onlyEOA {
        (Reward[] memory rewards, uint256 estimatedTotalReward) = _checkReward();
        require(estimatedTotalReward >= MIN_TOKENS_TO_REINVEST, "VariableRewardsStrategy::Reinvest amount too low");
        _reinvest(rewards);
    }

    function _convertRewardsIntoWAVAX(Reward[] memory rewards) private returns (uint256) {
        uint256 avaxAmount = rewardToken.balanceOf(address(this));
        for (uint256 i = 0; i < rewards.length; i++) {
            address reward = rewards[i].reward;
            address swapPair = rewardSwapPairs[reward];
            uint256 amount = rewards[i].amount;
            if (amount > 0) {
                if (reward == address(rewardToken)) {
                    uint256 balance = address(this).balance;
                    if (balance > 0) {
                        WAVAX.deposit{value: balance}();
                        avaxAmount = avaxAmount.add(amount);
                    }
                } else {
                    if (swapPair > address(0)) {
                        avaxAmount = avaxAmount.add(
                            DexLibrary.swap(amount, reward, address(rewardToken), IPair(swapPair))
                        );
                    }
                }
            }
        }
        return avaxAmount;
    }

    /**
     * @notice Reinvest rewards from staking contract to deposit tokens
     * @dev Reverts if the expected amount of tokens are not returned from the staking contract
     */
    function _reinvest(Reward[] memory rewards) private {
        _getRewards();
        uint256 amount = _convertRewardsIntoWAVAX(rewards);

        uint256 devFee = amount.mul(DEV_FEE_BIPS).div(BIPS_DIVISOR);
        if (devFee > 0) {
            rewardToken.safeTransfer(devAddr, devFee);
        }

        uint256 reinvestFee = amount.mul(REINVEST_REWARD_BIPS).div(BIPS_DIVISOR);
        if (reinvestFee > 0) {
            rewardToken.safeTransfer(msg.sender, reinvestFee);
        }

        uint256 depositTokenAmount = _convertRewardTokenToDepositToken(amount.sub(devFee).sub(reinvestFee));

        _stakeDepositTokens(depositTokenAmount);
        emit Reinvest(totalDeposits(), totalSupply);
    }

    function _stakeDepositTokens(uint256 amount) private {
        require(amount > 0, "VariableRewardsStrategy::Stake amount too low");
        _depositToStakingContract(amount);
    }

    function _checkReward() internal view returns (Reward[] memory, uint256) {
        Reward[] memory rewards = _pendingRewards();
        uint256 estimatedTotalReward = rewardToken.balanceOf(address(this));
        for (uint256 i = 0; i < rewards.length; i++) {
            address reward = rewards[i].reward;
            address swapPair = rewardSwapPairs[rewards[i].reward];
            uint256 balance = IERC20(reward).balanceOf(address(this));
            if (reward != address(rewardToken)) {
                uint256 amount = balance.add(rewards[i].amount);
                if (amount > 0 && swapPair > address(0)) {
                    estimatedTotalReward = estimatedTotalReward.add(
                        DexLibrary.estimateConversionThroughPair(amount, reward, address(rewardToken), IPair(swapPair))
                    );
                }
                rewards[i].amount = amount;
            } else {
                estimatedTotalReward = estimatedTotalReward.add(rewards[i].amount);
            }
        }
        return (rewards, estimatedTotalReward);
    }

    function checkReward() public view override returns (uint256) {
        (, uint256 estimatedTotalReward) = _checkReward();
        return estimatedTotalReward;
    }

    /**
     * @notice Estimate recoverable balance after withdraw fee
     * @return deposit tokens after withdraw fee
     */
    function estimateDeployedBalance() external view override returns (uint256) {
        uint256 depositBalance = totalDeposits();
        uint256 withdrawFee = _calculateWithdrawFee(depositBalance);
        return depositBalance.sub(withdrawFee);
    }

    function totalDeposits() public view override returns (uint256) {
        uint256 depositBalance = _getDepositBalance();
        return depositBalance;
    }

    function rescueDeployedFunds(uint256 minReturnAmountAccepted, bool disableDeposits) external override onlyOwner {
        uint256 balanceBefore = depositToken.balanceOf(address(this));
        _emergencyWithdraw();
        uint256 balanceAfter = depositToken.balanceOf(address(this));
        require(
            balanceAfter.sub(balanceBefore) >= minReturnAmountAccepted,
            "VariableRewardsStrategy::Emergency withdraw minimum return amount not reached"
        );
        emit Reinvest(totalDeposits(), totalSupply);
        if (DEPOSITS_ENABLED == true && disableDeposits == true) {
            updateDepositsEnabled(false);
        }
    }

    function _bip() internal view virtual returns (uint256) {
        return 10000;
    }

    /* VIRTUAL */
    function _convertRewardTokenToDepositToken(uint256 fromAmount) internal virtual returns (uint256 toAmount);

    function _depositToStakingContract(uint256 amount) internal virtual;

    function _withdrawFromStakingContract(uint256 amount) internal virtual returns (uint256 withdrawAmount);

    function _emergencyWithdraw() internal virtual;

    function _getRewards() internal virtual;

    function _pendingRewards() internal view virtual returns (Reward[] memory);

    function _getDepositBalance() internal view virtual returns (uint256 amount);
}
