// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../VariableRewardsStrategyForLP.sol";
import "../../../lib/SafeMath.sol";
import "../../../lib/SafeERC20.sol";
import "../../../interfaces/IBoosterFeeCollector.sol";

import "./interfaces/IVectorMainStakingJoe.sol";
import "./interfaces/IVectorJoePoolHelper.sol";

contract VectorStrategyForDexLP is VariableRewardsStrategyForLP {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 private constant JOE = IERC20(0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd);
    IERC20 private constant VTX = IERC20(0x5817D4F0b62A59b17f75207DA1848C2cE75e7AF4);

    IVectorMainStakingJoe public immutable vectorMainStaking;
    IBoosterFeeCollector public boosterFeeCollector;

    constructor(
        string memory _name,
        address _depositToken,
        SwapPairs memory _swapPairs,
        RewardSwapPairs[] memory _rewardSwapPairs,
        address _stakingContract,
        address _boosterFeeCollector,
        address _timelock,
        StrategySettings memory _strategySettings
    ) VariableRewardsStrategyForLP(_name, _depositToken, _swapPairs, _rewardSwapPairs, _timelock, _strategySettings) {
        vectorMainStaking = IVectorMainStakingJoe(_stakingContract);
        boosterFeeCollector = IBoosterFeeCollector(_boosterFeeCollector);
    }

    function updateBoosterFeeCollector(address _collector) public onlyOwner {
        boosterFeeCollector = IBoosterFeeCollector(_collector);
    }

    function _depositToStakingContract(uint256 _amount) internal override {
        IVectorJoePoolHelper vectorPoolHelper = _vectorPoolHelper();
        depositToken.approve(address(vectorPoolHelper), _amount);
        vectorPoolHelper.deposit(_amount);
        depositToken.approve(address(vectorPoolHelper), 0);
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 _withdrawAmount) {
        uint256 balanceBefore = depositToken.balanceOf(address(this));
        _vectorPoolHelper().withdraw(_amount);
        uint256 balanceAfter = depositToken.balanceOf(address(this));
        return balanceAfter.sub(balanceBefore);
    }

    function _emergencyWithdraw() internal override {
        IVectorJoePoolHelper vectorPoolHelper = _vectorPoolHelper();
        depositToken.approve(address(vectorPoolHelper), 0);
        vectorPoolHelper.withdraw(totalDeposits());
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        IVectorJoePoolHelper vectorPoolHelper = _vectorPoolHelper();
        uint256 count = rewardCount;
        Reward[] memory pendingRewards = new Reward[](count);
        (uint256 pendingVTX, uint256 pendingJOE) = vectorPoolHelper.earned(address(JOE));
        uint256 boostFee = boosterFeeCollector.calculateBoostFee(address(this), pendingJOE);
        pendingRewards[0] = Reward({reward: address(JOE), amount: pendingJOE.sub(boostFee)});
        pendingRewards[1] = Reward({reward: address(VTX), amount: pendingVTX});
        uint256 offset = 2;
        for (uint256 i = 0; i < count; i++) {
            address rewardToken = supportedRewards[i];
            if (rewardToken == address(JOE) || rewardToken == address(VTX)) {
                continue;
            }
            (, uint256 pendingAdditionalReward) = vectorPoolHelper.earned(address(rewardToken));
            pendingRewards[offset] = Reward({reward: rewardToken, amount: pendingAdditionalReward});
            offset++;
        }
        return pendingRewards;
    }

    function _getRewards() internal override {
        uint256 joeBalanceBefore = JOE.balanceOf(address(this));
        _vectorPoolHelper().getReward();
        uint256 amount = JOE.balanceOf(address(this)).sub(joeBalanceBefore);
        uint256 boostFee = boosterFeeCollector.calculateBoostFee(address(this), amount);
        JOE.safeTransfer(address(boosterFeeCollector), boostFee);
    }

    function totalDeposits() public view override returns (uint256) {
        return _vectorPoolHelper().balanceOf(address(this));
    }

    function _vectorPoolHelper() private view returns (IVectorJoePoolHelper) {
        (, , , , , address helper) = vectorMainStaking.getPoolInfo(address(depositToken));
        return IVectorJoePoolHelper(helper);
    }
}
