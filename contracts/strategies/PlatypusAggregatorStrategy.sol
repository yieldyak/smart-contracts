// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "../YakStrategyV2.sol";
import "../interfaces/IPair.sol";
import "../lib/DexLibrary.sol";
import "../lib/SafeERC20.sol";
import "../lib/PlatypusLibrary.sol";
import "../interfaces/IPlatypusPool.sol";
import "../interfaces/IBoosterFeeCollector.sol";

/**
 * @notice Adapter strategy for MasterChef.
 */
abstract contract PlatypusAggregatorStrategy is YakStrategyV2 {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

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

    IWAVAX private constant WAVAX = IWAVAX(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);
    IERC20 private constant PTP = IERC20(0x22d4002028f537599bE9f666d1c4Fa138522f9c8);
    address private immutable swapPairDepositToken;

    IPlatypusPool public immutable platypusPool;
    IPlatypusAsset public immutable platypusAsset;
    IBoosterFeeCollector public immutable boosterFeeCollector;
    uint256 public immutable PID;
    mapping(address => address) public rewardSwapPairs;
    uint256 public rewardCount = 1;

    constructor(
        string memory _name,
        address _depositToken,
        address _swapPairDepositToken,
        RewardSwapPairs[] memory _rewardSwapPairs,
        address _platypusPool,
        uint256 _pid,
        address _boosterFeeCollector,
        address _timelock,
        StrategySettings memory _strategySettings
    ) Ownable() {
        name = _name;
        depositToken = IERC20(_depositToken);
        rewardToken = IERC20(address(WAVAX));
        PID = _pid;
        devAddr = 0x2D580F9CF2fB2D09BC411532988F2aFdA4E7BefF;
        swapPairDepositToken = _swapPairDepositToken;

        for (uint256 i = 0; i < _rewardSwapPairs.length; i++) {
            _addReward(_rewardSwapPairs[i].reward, _rewardSwapPairs[i].swapPair);
        }

        platypusPool = IPlatypusPool(_platypusPool);
        platypusAsset = IPlatypusAsset(IPlatypusPool(_platypusPool).assetOf(_depositToken));
        boosterFeeCollector = IBoosterFeeCollector(_boosterFeeCollector);

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
                "PlatypusAggregatorStrategy::Swap pair does not contain reward token"
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
        require(DEPOSITS_ENABLED == true, "PlatypusAggregatorStrategy::Deposits disabled");
        if (MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST > 0) {
            (Reward[] memory rewards, uint256 estimatedTotalReward) = _checkReward();
            if (estimatedTotalReward > MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST) {
                _reinvest(rewards);
            }
        }
        require(
            depositToken.transferFrom(msg.sender, address(this), amount),
            "PlatypusAggregatorStrategy::Deposit token transfer failed"
        );
        uint256 depositFee = _calculateDepositFee(amount);
        _mint(account, getSharesForDepositTokens(amount.sub(depositFee)));
        _stakeDepositTokens(amount);
        emit Deposit(account, amount);
    }

    function _calculateDepositFee(uint256 amount) internal view virtual returns (uint256) {
        return PlatypusLibrary.calculateDepositFee(address(platypusPool), address(platypusAsset), amount);
    }

    function withdraw(uint256 amount) external override {
        uint256 depositTokenAmount = getDepositTokensForShares(amount);
        require(depositTokenAmount > 0, "PlatypusAggregatorStrategy::Withdraw amount too low");
        uint256 liquidity = _withdrawMasterchef(depositTokenAmount);
        uint256 withdrawAmount = _withdrawFromPool(liquidity);
        depositToken.safeTransfer(msg.sender, withdrawAmount);
        _burn(msg.sender, amount);
        emit Withdraw(msg.sender, depositTokenAmount);
    }

    function _withdrawFromPool(uint256 liquidity) internal returns (uint256 _withdrawAmount) {
        (uint256 minimumAmount, , ) = platypusPool.quotePotentialWithdraw(address(depositToken), liquidity);
        IERC20(address(platypusAsset)).approve(address(platypusPool), liquidity);
        _withdrawAmount = platypusPool.withdraw(
            address(depositToken),
            liquidity,
            minimumAmount,
            address(this),
            type(uint256).max
        );
        IERC20(address(platypusAsset)).approve(address(platypusPool), 0);
    }

    function _calculateWithdrawFee(uint256 amount) internal view virtual returns (uint256 _fee) {
        (, _fee, ) = platypusPool.quotePotentialWithdraw(address(depositToken), amount);
    }

    function reinvest() external override onlyEOA {
        (Reward[] memory rewards, uint256 estimatedTotalReward) = _checkReward();
        require(estimatedTotalReward >= MIN_TOKENS_TO_REINVEST, "PlatypusAggregatorStrategy::Reinvest amount too low");
        _reinvest(rewards);
    }

    function _convertRewardIntoWAVAX(Reward[] memory rewards) private returns (uint256) {
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
     * @dev Reverts if the expected amount of tokens are not returned from `MasterChef`
     */
    function _reinvest(Reward[] memory rewards) private {
        (, uint256 boostFee) = _pendingPTP();
        _getRewards();
        PTP.safeTransfer(address(boosterFeeCollector), boostFee);

        uint256 amount = _convertRewardIntoWAVAX(rewards);

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

    function _convertRewardTokenToDepositToken(uint256 fromAmount) internal returns (uint256 toAmount) {
        toAmount = DexLibrary.swap(
            fromAmount,
            address(rewardToken),
            address(depositToken),
            IPair(swapPairDepositToken)
        );
    }

    function _stakeDepositTokens(uint256 _amount) private {
        require(_amount > 0, "PlatypusAggregatorStrategy::Stake amount too low");
        uint256 depositFee = _calculateDepositFee(_amount);
        uint256 liquidity = PlatypusLibrary.depositTokenToAsset(address(platypusAsset), _amount, depositFee);
        depositToken.approve(address(platypusPool), _amount);
        platypusPool.deposit(address(depositToken), _amount, address(this), type(uint256).max);
        depositToken.approve(address(platypusPool), 0);
        _depositMasterchef(liquidity);
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
        uint256 assetBalance = _getDepositBalance();
        if (assetBalance == 0) return 0;
        (uint256 depositTokenBalance, uint256 fee, ) = platypusPool.quotePotentialWithdraw(
            address(depositToken),
            assetBalance
        );
        return depositTokenBalance.add(fee);
    }

    function rescueDeployedFunds(uint256 minReturnAmountAccepted, bool disableDeposits) external override onlyOwner {
        uint256 balanceBefore = depositToken.balanceOf(address(this));
        _emergencyWithdraw();
        uint256 balanceAfter = depositToken.balanceOf(address(this));
        require(
            balanceAfter.sub(balanceBefore) >= minReturnAmountAccepted,
            "PlatypusAggregatorStrategy::Emergency withdraw minimum return amount not reached"
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
    function _depositMasterchef(uint256 _amount) internal virtual;

    function _withdrawMasterchef(uint256 _amount) internal virtual returns (uint256 _withdrawAmount);

    function _emergencyWithdraw() internal virtual;

    function _getRewards() internal virtual;

    function _pendingPTP() internal view virtual returns (uint256 _ptpAmount, uint256 _boostFee);

    function _pendingRewards() internal view virtual returns (Reward[] memory);

    function _getDepositBalance() internal view virtual returns (uint256 _amount);
}
