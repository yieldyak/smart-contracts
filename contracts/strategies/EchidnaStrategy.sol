// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity 0.7.3;

import "../interfaces/IEchidnaBooster.sol";
import "../interfaces/IEchidnaRewardPool.sol";
import "../interfaces/IPlatypusPool.sol";
import "../interfaces/IPlatypusAsset.sol";
import "../interfaces/IMasterPlatypus.sol";
import "../lib/PlatypusLibrary.sol";
import "./MasterChefVariableRewardsStrategyForSAV2.sol";

contract EchidnaStrategy is MasterChefVariableRewardsStrategyForSAV2 {
    using SafeMath for uint256;

    IEchidnaBooster public immutable echidnaBooster;
    IEchidnaRewardPool public immutable echidnaRewardPool;
    IPlatypusPool public immutable platypusPool;
    IPlatypusAsset public immutable platypusAsset;

    constructor(
        string memory _name,
        address _depositToken,
        address _swapPairDepositToken,
        RewardSwapPairs[] memory _rewardSwapPairs,
        address _stakingContract,
        address _platypusPool,
        uint256 _pid,
        address _timelock,
        StrategySettings memory _strategySettings
    )
        MasterChefVariableRewardsStrategyForSAV2(
            _name,
            _depositToken,
            _swapPairDepositToken,
            _rewardSwapPairs,
            _timelock,
            _pid,
            _strategySettings
        )
    {
        platypusPool = IPlatypusPool(_platypusPool);
        echidnaBooster = IEchidnaBooster(_stakingContract);
        (, address rewardPool, ) = IEchidnaBooster(_stakingContract).pools(_pid);
        echidnaRewardPool = IEchidnaRewardPool(rewardPool);
        platypusAsset = IPlatypusAsset(IPlatypusPool(_platypusPool).assetOf(_depositToken));
    }

    function _depositMasterchef(uint256 _amount) internal override {
        uint256 depositFee = _calculateDepositFee(_amount);
        uint256 liquidity = PlatypusLibrary.depositTokenToAsset(address(platypusAsset), _amount, depositFee);
        depositToken.approve(address(platypusPool), _amount);
        platypusPool.deposit(address(depositToken), _amount, address(this), type(uint256).max);
        depositToken.approve(address(platypusPool), 0);
        IERC20(address(platypusAsset)).approve(address(echidnaBooster), liquidity);
        echidnaBooster.deposit(PID, liquidity);
        IERC20(address(platypusAsset)).approve(address(echidnaBooster), 0);
    }

    function _calculateDepositFee(uint256 amount) internal view override returns (uint256) {
        return PlatypusLibrary.calculateDepositFee(address(platypusPool), address(platypusAsset), amount);
    }

    function _withdrawMasterchef(uint256 _amount) internal override {
        uint256 balance = echidnaRewardPool.balanceOf(address(this));
        uint256 liquidity = _amount.mul(balance).div(_getDepositBalance());
        echidnaBooster.withdraw(PID, liquidity, false);
        (uint256 minimumAmount, , ) = platypusPool.quotePotentialWithdraw(address(depositToken), liquidity);
        IERC20(address(platypusAsset)).approve(address(platypusPool), liquidity);
        platypusPool.withdraw(address(depositToken), liquidity, minimumAmount, address(this), type(uint256).max);
        IERC20(address(platypusAsset)).approve(address(platypusPool), 0);
    }

    function _emergencyWithdraw() internal override {
        depositToken.approve(address(echidnaBooster), 0);
        echidnaBooster.withdrawAll(PID, false);
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        uint256 rewardCount = echidnaRewardPool.extraRewardsLength().add(1);
        Reward[] memory pendingRewards = new Reward[](rewardCount);
        pendingRewards[0] = Reward({
            reward: echidnaRewardPool.rewardToken(),
            amount: echidnaRewardPool.earned(address(this))
        });
        for (uint256 i = 1; i < rewardCount; i++) {
            IEchidnaRewardPool extraRewardPool = IEchidnaRewardPool(echidnaRewardPool.extraRewards(i));
            pendingRewards[i] = Reward({
                reward: extraRewardPool.rewardToken(),
                amount: extraRewardPool.earned(address(this))
            });
        }
        return pendingRewards;
    }

    function _getRewards() internal override {
        echidnaRewardPool.getReward(address(this), true);
    }

    function _getDepositBalance() internal view override returns (uint256 amount) {
        uint256 assetBalance = echidnaRewardPool.balanceOf(address(this));
        if (assetBalance == 0) return 0;
        (uint256 depositTokenBalance, uint256 fee, ) = platypusPool.quotePotentialWithdraw(
            address(depositToken),
            assetBalance
        );
        return depositTokenBalance.add(fee);
    }
}
