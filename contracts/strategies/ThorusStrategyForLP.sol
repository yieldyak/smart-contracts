// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity 0.7.3;

import "../interfaces/IThorusMaster.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IPair.sol";
import "../lib/DexLibrary.sol";
import "./MasterChefStrategyForLP.sol";

contract ThorusStrategyForLP is MasterChefStrategyForLP {
    IThorusMaster public thorusMaster;

    constructor(
        string memory _name,
        address _depositToken,
        address _rewardToken,
        address _nativeRewardToken,
        SwapPairs memory _swapPairs,
        address _stakingRewards,
        uint256 _pid,
        address _timelock,
        StrategySettings memory _strategySettings
    )
        MasterChefStrategyForLP(
            _name,
            _depositToken,
            _rewardToken,
            _nativeRewardToken,
            _swapPairs,
            _timelock,
            _pid,
            _strategySettings
        )
    {
        thorusMaster = IThorusMaster(_stakingRewards);
    }

    function _depositMasterchef(uint256 _pid, uint256 _amount) internal override {
        depositToken.approve(address(thorusMaster), _amount);
        thorusMaster.deposit(_pid, _amount, false);
    }

    function _withdrawMasterchef(uint256 _pid, uint256 _amount) internal override {
        thorusMaster.withdraw(_pid, _amount, false);
    }

    function _emergencyWithdraw(uint256 _pid) internal override {
        depositToken.approve(address(thorusMaster), 0);
        thorusMaster.emergencyWithdraw(_pid);
    }

    /**
     * @notice Returns pending rewards
     * @dev `rewarder` distributions are not considered
     */
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
        uint256 pendingThorus = thorusMaster.pendingThorus(_pid, _user);
        return (pendingThorus, 0, address(0));
    }

    function _getRewards(uint256 _pid) internal override {
        thorusMaster.deposit(_pid, 0, true);
    }

    function _getDepositBalance(uint256 _pid, address _user) internal view override returns (uint256 amount) {
        (amount, ) = thorusMaster.userInfo(_pid, _user);
    }

    function _getDepositFeeBips(uint256) internal pure override returns (uint256) {
        return 0;
    }

    function _getWithdrawFeeBips(uint256) internal pure override returns (uint256) {
        return 0;
    }

    function _bip() internal pure override returns (uint256) {
        return 10000;
    }
}
