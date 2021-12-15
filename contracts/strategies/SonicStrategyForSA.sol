// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity 0.7.3;

import "../interfaces/ISonicChef.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IPair.sol";
import "../lib/DexLibrary.sol";
import "./MasterChefStrategyForSA.sol";

contract SonicStrategyForSA is MasterChefStrategyForSA {
    using SafeMath for uint256;

    IWAVAX private constant WAVAX = IWAVAX(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);
    address private constant referrer = 0x2D580F9CF2fB2D09BC411532988F2aFdA4E7BefF;

    ISonicChef public sonicChef;

    constructor(
        string memory _name,
        address _depositToken,
        address _poolRewardToken,
        address _swapPairPoolReward,
        address _swapPairExtraReward,
        address _swapPairToken,
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
            _swapPairExtraReward,
            _swapPairToken,
            _timelock,
            _pid,
            _strategySettings
        )
    {
        sonicChef = ISonicChef(_stakingContract);
    }

    function _depositMasterchef(uint256 _pid, uint256 _amount) internal override {
        depositToken.approve(address(sonicChef), _amount);
        sonicChef.deposit(_pid, _amount, referrer);
    }

    function _withdrawMasterchef(uint256 _pid, uint256 _amount) internal override {
        sonicChef.withdraw(_pid, _amount);
    }

    function _emergencyWithdraw(uint256 _pid) internal override {
        sonicChef.emergencyWithdraw(_pid);
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
        return (sonicChef.pendingSonic(_pid, _user), 0, address(0));
    }

    function _getRewards(uint256 _pid) internal override {
        sonicChef.withdraw(_pid, 0);
    }

    function _getDepositBalance(uint256 pid, address user) internal view override returns (uint256 amount) {
        (amount, ) = sonicChef.userInfo(pid, user);
    }

    function _getDepositFeeBips(
        uint256 pid
    ) internal view override returns (uint256) {
        (,,,,uint16 depositFeeBP,,) = sonicChef.poolInfo(pid);
        return uint256(depositFeeBP);
    }

    function _getWithdrawFeeBips(
        uint256 pid
    ) internal view override returns (uint256) {
        (,,,,,uint16 withdrawFeeBP,) = sonicChef.poolInfo(pid);
        return uint256(withdrawFeeBP);
    }

    function _bip() internal pure override returns (uint256) {
        return 10000;
    }
}
