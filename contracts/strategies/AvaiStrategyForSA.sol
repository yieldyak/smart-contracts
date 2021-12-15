// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity 0.7.3;

import "../interfaces/IAvaiPodLeader.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IPair.sol";
import "../interfaces/IWAVAX.sol";
import "../lib/DexLibrary.sol";
import "./MasterChefStrategyForSA.sol";

// For OrcaStaking where reward is in AVAX. Has no deposit fee.
contract AvaiStrategyForSA is MasterChefStrategyForSA {
    using SafeMath for uint256;

    IAvaiPodLeader public podLeader;
    IWAVAX private constant WAVAX = IWAVAX(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);

    constructor(
        string memory _name,
        address _depositToken,
        address _swapPairToken, // swap rewardToken to depositToken
        address _poolRewardToken,
        address _swapPairPoolReward,
        address _swapPairExtraReward,
        address _stakingRewards,
        uint256 _pid,
        address _timelock,
        StrategySettings memory _strategySettings
    )
        MasterChefStrategyForSA(
            _name,
            _depositToken,
            address(WAVAX), /*rewardToken=*/
            _poolRewardToken,
            _swapPairPoolReward,
            _swapPairExtraReward,
            _swapPairToken,
            _timelock,
            _pid,
            _strategySettings
        )
    {
        podLeader = IAvaiPodLeader(_stakingRewards);
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

    receive() external payable {
        // TODO: verify sender after AVAI fixed their contract to use send instead of transfer.
        // require(msg.sender == address(stakingRewards), "AvaiStrategyForSA::payments not allowed");
    }

    function _getRewards(uint256 _pid) internal override {
        podLeader.deposit(_pid, 0);
        uint256 balance = address(this).balance;
        if (balance > 0) {
            WAVAX.deposit{value: balance}();
        }
    }

    function _getDepositBalance(uint256 pid, address user) internal view override returns (uint256 amount) {
        (amount, ) = podLeader.userInfo(pid, user);
    }

    function _getDepositFeeBips(uint256 pid) internal view override returns (uint256) {
        return 0;
    }

    function _getWithdrawFeeBips(uint256 pid) internal view override returns (uint256) {
        return 0;
    }

    function _bip() internal view override returns (uint256) {
        return 10000;
    }
}
