// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

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
        address _stakingRewards,
        uint256 _pid,
        address _timelock,
        uint256 _minTokensToReinvest,
        uint256 _adminFeeBips,
        uint256 _devFeeBips,
        uint256 _reinvestRewardBips
    )
        MasterChefStrategyForSA(
            _name,
            _depositToken,
            /*rewardToken=*/
            address(WAVAX),
            _swapPairToken,
            _stakingRewards,
            _timelock,
            _pid,
            _minTokensToReinvest,
            _adminFeeBips,
            _devFeeBips,
            _reinvestRewardBips
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

    function _pendingRewards(uint256 _pid, address _user) internal view override returns (uint256) {
        return podLeader.pendingRewards(_pid, _user);
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
