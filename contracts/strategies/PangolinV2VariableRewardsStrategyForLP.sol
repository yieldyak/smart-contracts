// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity ^0.7.0;

import "../interfaces/IMiniChefV2.sol";
import "../interfaces/IPangolinRewarder.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IPair.sol";
import "../lib/DexLibrary.sol";
import "./MasterChefVariableRewardsStrategyForLP.sol";

/**
 * notice: this strategy is not handling extra reward and rewarders.
 * we are waiting for the Pangolin team to provide additional information on the rewarders
 */
contract PangolinV2VariableRewardsStrategyForLP is MasterChefVariableRewardsStrategyForLP {
    using SafeMath for uint256;

    IMiniChefV2 public miniChef;
    address public swapPairRewardToken;
    address private poolRewardToken;

    constructor(
        string memory _name,
        address _depositToken,
        address _rewardToken,
        address _poolRewardToken,
        SwapPairs memory _swapPairs,
        address _stakingRewards,
        uint256 _pid,
        address _timelock,
        StrategySettings memory _strategySettings
    )
        MasterChefVariableRewardsStrategyForLP(
            _name,
            _depositToken,
            _rewardToken,
            _poolRewardToken,
            _swapPairs,
            _stakingRewards,
            _timelock,
            _pid,
            _strategySettings
        )
    {
        poolRewardToken = _poolRewardToken;
        miniChef = IMiniChefV2(_stakingRewards);
    }

    function _depositMasterchef(uint256 _pid, uint256 _amount) internal override {
        depositToken.approve(address(miniChef), _amount);
        miniChef.deposit(_pid, _amount, address(this));
    }

    function _withdrawMasterchef(uint256 _pid, uint256 _amount) internal override {
        miniChef.withdraw(_pid, _amount, address(this));
    }

    function _emergencyWithdraw(uint256 _pid) internal override {
        miniChef.emergencyWithdraw(_pid, address(this));
        depositToken.approve(address(miniChef), 0);
    }

    function _pendingRewards(uint256 _pid) internal view override returns (Reward[] memory) {
        uint256 poolRewardAmount = miniChef.pendingReward(_pid, address(this));
        IPangolinRewarder rewarder = IPangolinRewarder(miniChef.rewarder(_pid));
        Reward[] memory pendingRewards;
        if (address(rewarder) > address(0)) {
            (address[] memory rewardTokens, uint256[] memory rewardAmounts) = rewarder.pendingTokens(
                0,
                address(0),
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

    function _getRewards(uint256 _pid) internal override {
        miniChef.harvest(_pid, address(this));
    }

    function _getDepositBalance(uint256 pid) internal view override returns (uint256 amount) {
        (amount, ) = miniChef.userInfo(pid, address(this));
    }

    function _getDepositFeeBips(uint256 pid) internal pure override returns (uint256) {
        return 0;
    }

    function _getWithdrawFeeBips(uint256 pid) internal pure override returns (uint256) {
        return 0;
    }

    function _bip() internal pure override returns (uint256) {
        return 10000;
    }
}
