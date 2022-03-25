// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity 0.7.3;

import "../interfaces/IVectorPoolHelper.sol";
import "../interfaces/IBoosterFeeCollector.sol";
import "./VariableRewardsStrategyForSA.sol";

contract VectorStrategyForSA is VariableRewardsStrategyForSA {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 private constant PTP = IERC20(0x22d4002028f537599bE9f666d1c4Fa138522f9c8);
    IERC20 private constant VTX = IERC20(0x5817D4F0b62A59b17f75207DA1848C2cE75e7AF4);

    IVectorPoolHelper public immutable vectorPoolHelper;
    IBoosterFeeCollector public boosterFeeCollector;

    constructor(
        string memory _name,
        address _depositToken,
        address _swapPairDepositToken,
        RewardSwapPairs[] memory _rewardSwapPairs,
        address _stakingContract,
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
        Reward[] memory pendingRewards = new Reward[](2);
        (uint256 pendingVTX, uint256 pendingPTP) = vectorPoolHelper.earned(address(PTP));
        uint256 boostFee = boosterFeeCollector.calculateBoostFee(address(this), pendingPTP);
        pendingRewards[0] = Reward({reward: address(PTP), amount: pendingPTP.sub(boostFee)});
        pendingRewards[1] = Reward({reward: address(VTX), amount: pendingVTX});
        return pendingRewards;
    }

    function _getRewards() internal override {
        uint256 ptpBalanceBefore = PTP.balanceOf(address(this));
        vectorPoolHelper.getReward();
        uint256 boostFee = PTP.balanceOf(address(this)).sub(ptpBalanceBefore);
        boosterFeeCollector.calculateBoostFee(address(this), boostFee);
        PTP.safeTransfer(address(boosterFeeCollector), boostFee);
    }

    function _getDepositBalance() internal view override returns (uint256 amount) {
        return vectorPoolHelper.depositTokenBalance();
    }
}
