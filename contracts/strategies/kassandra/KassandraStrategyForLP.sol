// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../VariableRewardsStrategyForLP.sol";

import "./interfaces/IKassandraStaking.sol";

contract KassandraStrategyForLP is VariableRewardsStrategyForLP {
    address private constant KACY = 0xf32398dae246C5f672B52A54e9B413dFFcAe1A44;

    IKassandraStaking public stakingContract;
    uint256 public immutable PID;

    constructor(
        address _stakingContract,
        uint256 _pid,
        SwapPairs memory _swapPairs,
        RewardSwapPairs[] memory _rewardSwapPairs,
        BaseSettings memory _baseSettings,
        StrategySettings memory _strategySettings
    ) VariableRewardsStrategyForLP(_swapPairs, _rewardSwapPairs, _baseSettings, _strategySettings) {
        stakingContract = IKassandraStaking(_stakingContract);
        PID = _pid;
    }

    function _depositToStakingContract(uint256 _amount) internal override {
        IERC20(asset).approve(address(stakingContract), _amount);
        stakingContract.stake(PID, _amount, address(this), address(this));
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 _withdrawAmount) {
        stakingContract.withdraw(PID, _amount);
        return _amount;
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        uint256 pendingReward = stakingContract.earned(PID, address(this));
        Reward[] memory pendingRewards = new Reward[](1);
        pendingRewards[0] = Reward({reward: KACY, amount: pendingReward});
        return pendingRewards;
    }

    function _getRewards() internal override {
        stakingContract.getReward(PID);
    }

    function totalAssets() public view override returns (uint256) {
        return stakingContract.balanceOf(PID, address(this));
    }

    function _emergencyWithdraw() internal override {
        IERC20(asset).approve(address(stakingContract), 0);
        stakingContract.exit(PID);
    }
}
