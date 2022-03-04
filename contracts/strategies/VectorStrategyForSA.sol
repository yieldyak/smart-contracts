// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity ^0.7.0;

import "../interfaces/IVectorPoolHelper.sol";
import "../interfaces/IVectorMainStaking.sol";
import "../interfaces/IBoosterFeeCollector.sol";
import "../interfaces/IPlatypusPool.sol";
import "../interfaces/IPlatypusAsset.sol";
import "../lib/PlatypusLibrary.sol";
import "./VariableRewardsStrategyForSA.sol";

contract VectorStrategyForSA is VariableRewardsStrategyForSA {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 private constant PTP = IERC20(0x22d4002028f537599bE9f666d1c4Fa138522f9c8);
    IERC20 private constant VTX = IERC20(0x22d4002028f537599bE9f666d1c4Fa138522f9c8);

    IVectorPoolHelper public immutable vectorPoolHelper;
    IVectorMainStaking public immutable vectorMainStaking;
    IBoosterFeeCollector public boosterFeeCollector;
    IPlatypusPool public immutable platypusPool;
    IPlatypusAsset public immutable platypusAsset;

    constructor(
        string memory _name,
        address _depositToken,
        address _swapPairDepositToken,
        RewardSwapPairs[] memory _rewardSwapPairs,
        address _stakingContract,
        address _platypusPool,
        address _boosterFeeCollector,
        address _timelock,
        StrategySettings memory _strategySettings
    )
        VariableRewardsStrategyForSA(
            _name,
            _depositToken,
            _swapPairDepositToken,
            _rewardSwapPairs,
            _timelock,
            _strategySettings
        )
    {
        vectorPoolHelper = IVectorPoolHelper(_stakingContract);
        vectorMainStaking = IVectorMainStaking(IVectorPoolHelper(_stakingContract).mainStaking());
        platypusPool = IPlatypusPool(_platypusPool);
        platypusAsset = IPlatypusAsset(IPlatypusPool(_platypusPool).assetOf(_depositToken));
        boosterFeeCollector = IBoosterFeeCollector(_boosterFeeCollector);
    }

    function updateBoosterFeeCollector(address _collector) public onlyDev {
        boosterFeeCollector = IBoosterFeeCollector(_collector);
    }

    function _depositToStakingContract(uint256 _amount) internal override {
        depositToken.approve(address(vectorPoolHelper.mainStaking()), _amount);
        vectorPoolHelper.deposit(_amount);
        depositToken.approve(address(vectorPoolHelper.mainStaking()), 0);
    }

    function _calculateDepositFee(uint256 amount) internal view override returns (uint256) {
        return PlatypusLibrary.calculateDepositFee(address(platypusPool), address(platypusAsset), amount);
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 _withdrawAmount) {
        uint256 balanceBefore = depositToken.balanceOf(address(this));
        vectorPoolHelper.withdraw(_amount, 0);
        uint256 balanceAfter = depositToken.balanceOf(address(this));
        return balanceAfter.sub(balanceBefore);
    }

    function _emergencyWithdraw() internal override {
        depositToken.approve(address(vectorPoolHelper), 0);
        vectorPoolHelper.withdraw(_getDepositBalance(), 0);
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        uint256 rewardCount = 2;
        Reward[] memory pendingRewards = new Reward[](rewardCount);
        (uint256 pendingPTP, uint256 pendingVTX, uint256 boostFee) = _pendingRewardsInternal();
        pendingRewards[0] = Reward({reward: address(PTP), amount: pendingPTP.sub(boostFee)});
        pendingRewards[1] = Reward({reward: address(VTX), amount: pendingVTX});
        return pendingRewards;
    }

    function _getRewards() internal override {
        (, , uint256 boostFee) = _pendingRewardsInternal();
        vectorPoolHelper.getReward();
        PTP.safeTransfer(address(boosterFeeCollector), boostFee);
    }

    function _pendingRewardsInternal()
        internal
        view
        returns (
            uint256 _pendingPTP,
            uint256 _pendingVTX,
            uint256 _boostFee
        )
    {
        (_pendingVTX, _pendingPTP) = vectorPoolHelper.earned(address(depositToken));
        _boostFee = boosterFeeCollector.calculateBoostFee(address(this), _pendingPTP);
    }

    function _getDepositBalance() internal view override returns (uint256 amount) {
        return vectorPoolHelper.depositTokenBalance();
    }
}
