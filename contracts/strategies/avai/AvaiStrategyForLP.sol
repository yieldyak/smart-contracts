// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../VariableRewardsStrategyForLP.sol";
import "../../interfaces/IERC20.sol";

import "./interfaces/IAvaiPodLeader.sol";

contract AvaiStrategyForLP is VariableRewardsStrategyForLP {
    address private constant ORCA = 0x8B1d98A91F853218ddbb066F20b8c63E782e2430;

    IAvaiPodLeader public podLeader;
    uint256 public immutable PID;

    constructor(
        address _stakingContract,
        uint256 _pid,
        SwapPairs memory _swapPairs,
        RewardSwapPairs[] memory _rewardSwapPairs,
        BaseSettings memory _baseSettings,
        StrategySettings memory _strategySettings
    ) VariableRewardsStrategyForLP(_swapPairs, _rewardSwapPairs, _baseSettings, _strategySettings) {
        podLeader = IAvaiPodLeader(_stakingContract);
        PID = _pid;
    }

    function _depositToStakingContract(uint256 _amount) internal override {
        podLeader.deposit(PID, _amount);
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 _withdrawAmount) {
        podLeader.withdraw(PID, _amount);
        return _amount;
    }

    function _emergencyWithdraw() internal override {
        podLeader.emergencyWithdraw(PID);
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        Reward[] memory pendingRewards = new Reward[](1);
        pendingRewards[0] = Reward({reward: ORCA, amount: podLeader.pendingRewards(PID, address(this))});
        return pendingRewards;
    }

    function _getRewards() internal override {
        podLeader.deposit(PID, 0);
    }

    function totalAssets() public view override returns (uint256) {
        (uint256 amount, ) = podLeader.userInfo(PID, address(this));
        return amount;
    }

    function _getDepositFeeBips() internal view override returns (uint256) {
        (, , , , , uint256 fees) = podLeader.poolInfo(PID);
        return fees;
    }

    function _bip() internal pure override returns (uint256) {
        return 10000;
    }
}
