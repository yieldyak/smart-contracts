// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity ^0.7.0;

import "../interfaces/IMiniChefV2.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IPair.sol";
import "../lib/DexLibrary.sol";
import "./MasterChefStrategyForLP.sol";

contract PangolinV2StrategyForLP is MasterChefStrategyForLP {
    using SafeMath for uint256;

    IMiniChefV2 public miniChef;
    address public swapPairRewardToken;

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
            _stakingRewards,
            _timelock,
            _pid,
            _strategySettings
        )
    {
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
        return (miniChef.pendingRewards(_pid, _user), 0, address(0));
    }

    function _getRewards(uint256 _pid) internal override {
        miniChef.deposit(_pid, 0, address(this));
    }

    function _getDepositBalance(uint256 pid, address user) internal view override returns (uint256 amount) {
        (amount, ) = miniChef.userInfo(pid, user);
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
