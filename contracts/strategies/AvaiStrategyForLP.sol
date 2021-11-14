// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity ^0.7.0;

import "../interfaces/IAvaiPodLeader.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IPair.sol";
import "../lib/DexLibrary.sol";
import "./MasterChefStrategyForLP.sol";

contract AvaiStrategyForLP is MasterChefStrategyForLP {
    using SafeMath for uint256;

    IAvaiPodLeader public podLeader;
    address public nativeRewardToken;
    address public swapPairRewardToken;
    uint256 public depositFeeBips;

    constructor(
        string memory _name,
        address _depositToken,
        address _rewardToken,
        address _nativeRewardToken,
        SwapPairs memory _swapPairs,
        address _stakingRewards,
        uint256 _pid,
        address _timelock,
        uint256 _depositFeeBips,
        StrategySettings memory _strategySettings
    )
        MasterChefStrategyForLP(
            _name,
            _depositToken,
            _rewardToken,
            _nativeRewardToken,
            _swapPairs,
            _stakingRewards,
            _timelock,
            _pid,
            _strategySettings
        )
    {
        podLeader = IAvaiPodLeader(_stakingRewards);
        depositFeeBips = _depositFeeBips;
        nativeRewardToken = _nativeRewardToken;
    }

    function _depositMasterchef(uint256 _pid, uint256 _amount) internal override {
        podLeader.deposit(_pid, _amount);
    }

    function _withdrawMasterchef(uint256 _pid, uint256 _amount) internal override {
        podLeader.withdraw(_pid, _amount);
    }

    function _emergencyWithdraw(uint256 _pid) internal override {
        podLeader.emergencyWithdraw(_pid);
    }

    function _pendingRewards(uint256 _pid, address _user)
        internal
        view
        override
        returns (
            uint256,
            uint256,
            address
        )
    {
        return (podLeader.pendingRewards(_pid, _user), 0, address(0));
    }

    function _getRewards(uint256 _pid) internal override {
        podLeader.deposit(_pid, 0);
    }

    function _getDepositBalance(uint256 pid, address user) internal view override returns (uint256 amount) {
        (amount, ) = podLeader.userInfo(pid, user);
    }

    function setDepositFeeBips(uint256 _depositFeeBips) external onlyOwner {
        depositFeeBips = _depositFeeBips;
    }

    function _getDepositFeeBips(uint256 pid) internal view override returns (uint256) {
        return depositFeeBips;
    }

    function _getWithdrawFeeBips(uint256 pid) internal pure override returns (uint256) {
        return 0;
    }

    function _bip() internal pure override returns (uint256) {
        return 10000;
    }
}
