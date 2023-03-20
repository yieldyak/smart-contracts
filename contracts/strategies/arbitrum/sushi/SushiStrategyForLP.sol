// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../../VariableRewardsStrategyForLP.sol";

import "./interfaces/IMiniChefV2.sol";
import "./interfaces/ITreasureRewarder.sol";

contract SushiStrategyForLP is VariableRewardsStrategyForLP {
    address private constant SUSHI = 0xd4d42F0b6DEF4CE0383636770eF773390d85c61A;

    IMiniChefV2 public miniChef;
    uint256 public immutable PID;

    constructor(
        address _stakingContract,
        uint256 _pid,
        SwapPairs memory _swapPairs,
        VariableRewardsStrategySettings memory _variableRewardsStrategySettings,
        StrategySettings memory _strategySettings
    ) VariableRewardsStrategyForLP(_swapPairs, _variableRewardsStrategySettings, _strategySettings) {
        PID = _pid;
        miniChef = IMiniChefV2(_stakingContract);
    }

    function _depositToStakingContract(uint256 _amount, uint256) internal override {
        depositToken.approve(address(miniChef), _amount);
        miniChef.deposit(PID, _amount, address(this));
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 _withdrawAmount) {
        miniChef.withdraw(PID, _amount, address(this));
        _withdrawAmount = _amount;
    }

    function _emergencyWithdraw() internal override {
        miniChef.emergencyWithdraw(PID, address(this));
        depositToken.approve(address(miniChef), 0);
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        uint256 poolRewardAmount = miniChef.pendingSushi(PID, address(this));
        ITreasureRewarder rewarder = ITreasureRewarder(miniChef.rewarder(PID));
        Reward[] memory pendingRewards;
        if (address(rewarder) > address(0)) {
            (address[] memory rewardTokens, uint256[] memory rewardAmounts) = rewarder.pendingTokens(
                0,
                address(this),
                poolRewardAmount
            );
            pendingRewards = new Reward[](rewardTokens.length + 1);
            for (uint256 i = 0; i < rewardTokens.length; i++) {
                pendingRewards[i + 1] = Reward({reward: rewardTokens[i], amount: rewardAmounts[i]});
            }
        } else {
            pendingRewards = new Reward[](1);
        }
        pendingRewards[0] = Reward({reward: SUSHI, amount: poolRewardAmount});
        return pendingRewards;
    }

    function _getRewards() internal override {
        miniChef.harvest(PID, address(this));
    }

    function totalDeposits() public view override returns (uint256) {
        (uint256 amount, ) = miniChef.userInfo(PID, address(this));
        return amount;
    }
}
