// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../VariableRewardsStrategyForLP.sol";
import "../../interfaces/IBoosterFeeCollector.sol";
import "../../lib/SafeMath.sol";
import "../../lib/SafeERC20.sol";

import "./interfaces/ISteakMasterChef.sol";

contract SteakStrategyForLP is VariableRewardsStrategyForLP {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 private constant JOE = IERC20(0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd);

    ISteakMasterChef public immutable steakMasterChef;
    uint256 public immutable PID;
    IBoosterFeeCollector public boosterFeeCollector;

    constructor(
        address _stakingContract,
        uint256 _pid,
        address _boosterFeeCollector,
        SwapPairs memory _swapPairs,
        RewardSwapPairs[] memory _rewardSwapPairs,
        BaseSettings memory _baseSettings,
        StrategySettings memory _strategySettings
    ) VariableRewardsStrategyForLP(_swapPairs, _rewardSwapPairs, _baseSettings, _strategySettings) {
        steakMasterChef = ISteakMasterChef(_stakingContract);
        boosterFeeCollector = IBoosterFeeCollector(_boosterFeeCollector);
        PID = _pid;
    }

    function updateBoosterFeeCollector(address _collector) public onlyOwner {
        boosterFeeCollector = IBoosterFeeCollector(_collector);
    }

    function _depositToStakingContract(uint256 _amount) internal override {
        IERC20(asset).approve(address(steakMasterChef), _amount);
        steakMasterChef.deposit(PID, _amount);
        IERC20(asset).approve(address(steakMasterChef), 0);
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 _withdrawAmount) {
        steakMasterChef.withdraw(PID, _amount);
        return _amount;
    }

    function _emergencyWithdraw() internal override {
        IERC20(asset).approve(address(steakMasterChef), 0);
        steakMasterChef.withdraw(PID, totalDeposits());
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        Reward[] memory pendingRewards = new Reward[](1);
        uint256 pendingJOE = steakMasterChef.pendingJoe(PID, address(this));
        uint256 boostFee = boosterFeeCollector.calculateBoostFee(address(this), pendingJOE);
        pendingRewards[0] = Reward({reward: address(JOE), amount: pendingJOE.sub(boostFee)});
        return pendingRewards;
    }

    function _getRewards() internal override {
        uint256 joeBalanceBefore = JOE.balanceOf(address(this));
        steakMasterChef.deposit(PID, 0);
        uint256 amount = JOE.balanceOf(address(this)).sub(joeBalanceBefore);
        uint256 boostFee = boosterFeeCollector.calculateBoostFee(address(this), amount);
        JOE.safeTransfer(address(boosterFeeCollector), boostFee);
    }

    function totalAssets() public view override returns (uint256) {
        (uint256 amount, ) = steakMasterChef.userInfo(PID, address(this));
        return amount;
    }
}
