// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../VariableRewardsStrategyForLP.sol";
import "../../interfaces/IERC20.sol";
import "../../interfaces/IPair.sol";
import "../../lib/DexLibrary.sol";

import "./interfaces/IMiniChefV2.sol";
import "./interfaces/IPangolinRewarder.sol";

contract PangolinV2VariableRewardsStrategyForLP is VariableRewardsStrategyForLP {
    using SafeMath for uint256;

    IMiniChefV2 public miniChef;
    uint256 public immutable PID;
    address private poolRewardToken;

    constructor(
        address _poolRewardToken,
        address _stakingContract,
        uint256 _pid,
        SwapPairs memory _swapPairs,
        RewardSwapPairs[] memory _rewardSwapPairs,
        BaseSettings memory _baseSettings,
        StrategySettings memory _strategySettings
    ) VariableRewardsStrategyForLP(_swapPairs, _rewardSwapPairs, _baseSettings, _strategySettings) {
        poolRewardToken = _poolRewardToken;
        PID = _pid;
        miniChef = IMiniChefV2(_stakingContract);
    }

    function _depositToStakingContract(uint256 _amount) internal override {
        IERC20(asset).approve(address(miniChef), _amount);
        miniChef.deposit(PID, _amount, address(this));
        IERC20(asset).approve(address(miniChef), 0);
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 _withdrawAmount) {
        miniChef.withdraw(PID, _amount, address(this));
        _withdrawAmount = _amount;
    }

    function _emergencyWithdraw() internal override {
        miniChef.emergencyWithdraw(PID, address(this));
        IERC20(asset).approve(address(miniChef), 0);
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        uint256 poolRewardAmount = miniChef.pendingReward(PID, address(this));
        IPangolinRewarder rewarder = IPangolinRewarder(miniChef.rewarder(PID));
        Reward[] memory pendingRewards;
        if (address(rewarder) > address(0)) {
            (address[] memory rewardTokens, uint256[] memory rewardAmounts) = rewarder.pendingTokens(
                0,
                address(this),
                poolRewardAmount
            );
            pendingRewards = new Reward[](rewardTokens.length.add(1));
            for (uint256 i = 0; i < rewardTokens.length; i++) {
                pendingRewards[i + 1] = Reward({reward: rewardTokens[i], amount: rewardAmounts[i]});
            }
        } else {
            pendingRewards = new Reward[](1);
        }
        pendingRewards[0] = Reward({reward: poolRewardToken, amount: poolRewardAmount});
        return pendingRewards;
    }

    function _getRewards() internal override {
        miniChef.harvest(PID, address(this));
    }

    function totalAssets() public view override returns (uint256) {
        (uint256 amount, ) = miniChef.userInfo(PID, address(this));
        return amount;
    }
}
