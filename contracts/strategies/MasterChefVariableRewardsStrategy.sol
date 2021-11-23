// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "../YakStrategyV2.sol";
import "../interfaces/IPair.sol";
import "../lib/DexLibrary.sol";

/**
 * @notice Adapter strategy for MasterChef.
 */
abstract contract MasterChefVariableRewardsStrategy is YakStrategyV2 {
    using SafeMath for uint256;

    IWAVAX private constant WAVAX = IWAVAX(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);

    struct Reward {
        address reward;
        uint256 amount;
    }

    struct StrategySettings {
        uint256 minTokensToReinvest;
        uint256 adminFeeBips;
        uint256 devFeeBips;
        uint256 reinvestRewardBips;
    }

    uint256 public immutable PID;
    address private stakingContract;

    // reward -> swapPair
    mapping(address => address) public rewardSwapPairs;
    uint256 public rewardCount = 1;

    constructor(
        string memory _name,
        address _depositToken,
        address _ecosystemToken,
        address _poolRewardToken,
        address _swapPairPoolReward,
        address _stakingContract,
        address _timelock,
        uint256 _pid,
        StrategySettings memory _strategySettings
    ) Ownable() {
        name = _name;
        depositToken = IERC20(_depositToken);
        rewardToken = IERC20(_ecosystemToken);
        PID = _pid;
        devAddr = 0x2D580F9CF2fB2D09BC411532988F2aFdA4E7BefF;
        stakingContract = _stakingContract;
        rewardSwapPairs[_poolRewardToken] = _swapPairPoolReward;

        updateMinTokensToReinvest(_strategySettings.minTokensToReinvest);
        updateAdminFee(_strategySettings.adminFeeBips);
        updateDevFee(_strategySettings.devFeeBips);
        updateReinvestReward(_strategySettings.reinvestRewardBips);
        updateDepositsEnabled(true);
        transferOwnership(_timelock);
        emit Reinvest(0, 0);
    }

    function addReward(address _rewardToken, address _swapPair) public onlyDev {
        if (_rewardToken == IPair(_swapPair).token0()) {
            require(
                IPair(_swapPair).token1() == address(rewardToken),
                "Swap pair swapPairPoolReward does not contain reward token"
            );
        } else {
            require(
                IPair(_swapPair).token0() == address(rewardToken) && IPair(_swapPair).token1() == _rewardToken,
                "Swap pair swapPairPoolReward does not contain reward token"
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
        require(DEPOSITS_ENABLED == true, "MasterChefStrategyV1::_deposit");
        if (MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST > 0) {
            (Reward[] memory rewards, uint256 estimatedTotalReward) = _checkReward();
            if (estimatedTotalReward > MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST) {
                _reinvest(rewards);
            }
        }
        require(depositToken.transferFrom(msg.sender, address(this), amount), "MasterChefStrategyV1::transfer failed");
        uint256 depositFeeBips = _getDepositFeeBips(PID);
        uint256 depositFee = amount.mul(depositFeeBips).div(_bip());
        _mint(account, getSharesForDepositTokens(amount.sub(depositFee)));
        _stakeDepositTokens(amount);
        emit Deposit(account, amount);
    }

    function withdraw(uint256 amount) external override {
        uint256 depositTokenAmount = getDepositTokensForShares(amount);
        require(depositTokenAmount > 0, "MasterChefStrategyV1::withdraw");
        _withdrawDepositTokens(depositTokenAmount);
        uint256 withdrawFeeBips = _getWithdrawFeeBips(PID);
        uint256 withdrawFee = depositTokenAmount.mul(withdrawFeeBips).div(_bip());
        _safeTransfer(address(depositToken), msg.sender, depositTokenAmount.sub(withdrawFee));
        _burn(msg.sender, amount);
        emit Withdraw(msg.sender, depositTokenAmount);
    }

    function _withdrawDepositTokens(uint256 amount) private {
        _withdrawMasterchef(PID, amount);
    }

    function reinvest() external override onlyEOA {
        (Reward[] memory rewards, uint256 estimatedTotalReward) = _checkReward();
        require(estimatedTotalReward >= MIN_TOKENS_TO_REINVEST, "MasterChefStrategyV1::reinvest");
        _reinvest(rewards);
    }

    function _convertRewardIntoWAVAX(Reward[] memory rewards) private returns (uint256) {
        uint256 avaxAmount = 0;
        for (uint256 i = 0; i < rewards.length; i++) {
            address reward = rewards[i].reward;
            address swapPair = rewardSwapPairs[reward];
            uint256 amount = rewards[i].amount;
            if (reward != address(rewardToken)) {
                if (amount > 0 && swapPair > address(0)) {
                    avaxAmount = avaxAmount.add(DexLibrary.swap(amount, reward, address(rewardToken), IPair(swapPair)));
                }
            } else {
                uint256 balance = address(this).balance;
                if (balance > 0) {
                    WAVAX.deposit{value: balance}();
                }
                avaxAmount = avaxAmount.add(amount);
            }
        }
        return avaxAmount;
    }

    /**
     * @notice Reinvest rewards from staking contract to deposit tokens
     * @dev Reverts if the expected amount of tokens are not returned from `MasterChef`
     */
    function _reinvest(Reward[] memory rewards) private {
        _getRewards(PID);
        uint256 amount = _convertRewardIntoWAVAX(rewards);

        uint256 devFee = amount.mul(DEV_FEE_BIPS).div(BIPS_DIVISOR);
        if (devFee > 0) {
            _safeTransfer(address(rewardToken), devAddr, devFee);
        }

        uint256 reinvestFee = amount.mul(REINVEST_REWARD_BIPS).div(BIPS_DIVISOR);
        if (reinvestFee > 0) {
            _safeTransfer(address(rewardToken), msg.sender, reinvestFee);
        }

        uint256 depositTokenAmount = _convertRewardTokenToDepositToken(amount.sub(devFee).sub(reinvestFee));

        _stakeDepositTokens(depositTokenAmount);
        emit Reinvest(totalDeposits(), totalSupply);
    }

    function _stakeDepositTokens(uint256 amount) private {
        require(amount > 0, "MasterChefStrategyV1::_stakeDepositTokens");
        _depositMasterchef(PID, amount);
    }

    /**
     * @notice Safely transfer using an anonymosu ERC20 token
     * @dev Requires token to return true on transfer
     * @param token address
     * @param to recipient address
     * @param value amount
     */
    function _safeTransfer(
        address token,
        address to,
        uint256 value
    ) private {
        require(IERC20(token).transfer(to, value), "MasterChefStrategyV1::TRANSFER_FROM_FAILED");
    }

    function _checkReward() internal view returns (Reward[] memory, uint256) {
        Reward[] memory rewards = _pendingRewards(PID);
        uint256 estimatedTotalReward = 0;
        for (uint256 i = 0; i < rewards.length; i++) {
            address reward = rewards[i].reward;
            address swapPair = rewardSwapPairs[rewards[i].reward];
            uint256 amount = rewards[i].amount;
            if (reward != address(rewardToken)) {
                if (amount > 0 && swapPair > address(0)) {
                    estimatedTotalReward = estimatedTotalReward.add(
                        DexLibrary.estimateConversionThroughPair(amount, reward, address(rewardToken), IPair(swapPair))
                    );
                }
            } else {
                estimatedTotalReward = estimatedTotalReward.add(amount);
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
        uint256 withdrawFeeBips = _getWithdrawFeeBips(PID);
        uint256 withdrawFee = depositBalance.mul(withdrawFeeBips).div(_bip());
        return depositBalance.sub(withdrawFee);
    }

    function totalDeposits() public view override returns (uint256) {
        uint256 depositBalance = _getDepositBalance(PID);
        return depositBalance;
    }

    function rescueDeployedFunds(uint256 minReturnAmountAccepted, bool disableDeposits) external override onlyOwner {
        uint256 balanceBefore = depositToken.balanceOf(address(this));
        _emergencyWithdraw(PID);
        uint256 balanceAfter = depositToken.balanceOf(address(this));
        require(
            balanceAfter.sub(balanceBefore) >= minReturnAmountAccepted,
            "MasterChefStrategyV1::rescueDeployedFunds"
        );
        emit Reinvest(totalDeposits(), totalSupply);
        if (DEPOSITS_ENABLED == true && disableDeposits == true) {
            updateDepositsEnabled(false);
        }
    }

    /* VIRTUAL */
    function _convertRewardTokenToDepositToken(uint256 fromAmount) internal virtual returns (uint256 toAmount);

    function _depositMasterchef(uint256 pid, uint256 amount) internal virtual;

    function _withdrawMasterchef(uint256 pid, uint256 amount) internal virtual;

    function _emergencyWithdraw(uint256 pid) internal virtual;

    function _getRewards(uint256 pid) internal virtual;

    function _pendingRewards(uint256 pid) internal view virtual returns (Reward[] memory);

    function _getDepositBalance(uint256 pid) internal view virtual returns (uint256 amount);

    function _getDepositFeeBips(uint256 pid) internal view virtual returns (uint256);

    function _getWithdrawFeeBips(uint256 pid) internal view virtual returns (uint256);

    function _bip() internal view virtual returns (uint256);
}
