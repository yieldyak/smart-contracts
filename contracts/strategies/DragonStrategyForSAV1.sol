// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity ^0.7.0;

import "../interfaces/IDragonChef.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IPair.sol";
import "../interfaces/IWAVAX.sol";
import "../lib/DexLibrary.sol";
import "./MasterChefStrategyForSA.sol";

contract DragonStrategyForSAV1 is MasterChefStrategyForSA {
    using SafeMath for uint256;

    IDragonChef public dragonChef;
    IWAVAX private constant WAVAX = IWAVAX(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);

    constructor(
        string memory _name,
        address _depositToken,
        address _swapPairToken, // swap rewardToken to depositToken
        address _poolRewardToken,
        address _swapPairPoolReward,
        address _stakingContract,
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
            _swapPairToken,
            _stakingContract,
            _timelock,
            _pid,
            _strategySettings
        )
    {
        dragonChef = IDragonChef(_stakingContract);
    }

    function _depositMasterchef(uint256 _pid, uint256 _amount) internal override {
        dragonChef.deposit(_pid, _amount);
    }

    function _withdrawMasterchef(uint256 _pid, uint256 _amount) internal override {
        dragonChef.withdraw(_pid, _amount);
    }

    function _emergencyWithdraw(uint256 _pid) internal override {
        dragonChef.emergencyWithdraw(_pid);
    }

    function _pendingRewards(uint256 _pid, address _user) internal view override returns (uint256) {
        return dragonChef.pendingDcau(_pid, _user);
    }

    function _getRewards(uint256 _pid) internal override {
        dragonChef.deposit(_pid, 0);
    }

    function _getDepositBalance(uint256 pid, address user) internal view override returns (uint256 amount) {
        (amount, ) = dragonChef.userInfo(pid, user);
    }

    function _getDepositFeeBips(uint256 pid) internal view override returns (uint256) {
        IDragonChef.PoolInfo memory poolInfo = dragonChef.poolInfo(pid);
        return poolInfo.depositFeeBP;
    }

    function _getWithdrawFeeBips(uint256 pid) internal view override returns (uint256) {
        return 0;
    }

    function _bip() internal view override returns (uint256) {
        return 10000;
    }
}
