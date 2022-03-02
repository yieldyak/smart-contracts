// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity 0.7.3;

import "../interfaces/IEchidnaBooster.sol";
import "../interfaces/IEchidnaRewardPool.sol";
import "./PlatypusAggregatorStrategy.sol";

contract EchidnaStrategy is PlatypusAggregatorStrategy {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IEchidnaBooster public immutable echidnaBooster;
    IEchidnaRewardPool public immutable echidnaRewardPool;

    constructor(
        string memory _name,
        address _depositToken,
        address _swapPairDepositToken,
        RewardSwapPairs[] memory _rewardSwapPairs,
        address _stakingContract,
        address _platypusPool,
        uint256 _pid,
        address _boosterFeeCollector,
        address _timelock,
        StrategySettings memory _strategySettings
    )
        PlatypusAggregatorStrategy(
            _name,
            _depositToken,
            _swapPairDepositToken,
            _rewardSwapPairs,
            _platypusPool,
            _pid,
            _boosterFeeCollector,
            _timelock,
            _strategySettings
        )
    {
        echidnaBooster = IEchidnaBooster(_stakingContract);
        (, address rewardPool, ) = IEchidnaBooster(_stakingContract).pools(_pid);
        echidnaRewardPool = IEchidnaRewardPool(rewardPool);
    }

    function _depositMasterchef(uint256 _amount) internal override {
        IERC20(address(platypusAsset)).approve(address(echidnaBooster), _amount);
        echidnaBooster.deposit(PID, _amount);
        IERC20(address(platypusAsset)).approve(address(echidnaBooster), 0);
    }

    function _withdrawMasterchef(uint256 _amount) internal override returns (uint256 _liquidity) {
        uint256 balance = echidnaRewardPool.balanceOf(address(this));
        _liquidity = _amount.mul(balance).div(totalDeposits());
        echidnaBooster.withdraw(PID, _liquidity, false);
    }

    function _emergencyWithdraw() internal override {
        depositToken.approve(address(echidnaBooster), 0);
        echidnaBooster.withdrawAll(PID, false);
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        uint256 rewardCount = echidnaRewardPool.extraRewardsLength().add(1);
        Reward[] memory pendingRewards = new Reward[](rewardCount);
        (uint256 ptpAmount, uint256 boostFee) = _pendingPTP();
        pendingRewards[0] = Reward({reward: echidnaRewardPool.rewardToken(), amount: ptpAmount.sub(boostFee)});
        for (uint256 i = 1; i < rewardCount; i++) {
            IEchidnaRewardPool extraRewardPool = IEchidnaRewardPool(echidnaRewardPool.extraRewards(i));
            pendingRewards[i] = Reward({
                reward: extraRewardPool.rewardToken(),
                amount: extraRewardPool.earned(address(this))
            });
        }
        return pendingRewards;
    }

    function _pendingPTP() internal view override returns (uint256 _ptpAmount, uint256 _boostFee) {
        _ptpAmount = echidnaRewardPool.earned(address(this));
        _boostFee = boosterFeeCollector.calculateBoostFee(address(this), _ptpAmount);
    }

    function _getRewards() internal override {
        echidnaRewardPool.getReward(address(this), true);
    }

    function _getDepositBalance() internal view override returns (uint256 _assetBalance) {
        _assetBalance = echidnaRewardPool.balanceOf(address(this));
    }
}
