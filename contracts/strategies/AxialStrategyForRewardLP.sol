// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity ^0.7.0;

import "../interfaces/IAxialChef.sol";
import "../interfaces/IAxialSwap.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IPair.sol";
import "../lib/DexLibrary.sol";
import "./MasterChefStrategyForLP.sol";

contract AxialStrategyForRewardLP is MasterChefStrategyForLP {
    using SafeMath for uint256;

    IWAVAX private constant WAVAX = IWAVAX(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);

    IAxialChef public axialChef;

    constructor(
        string memory _name,
        address _depositToken,
        address _poolRewardToken,
        SwapPairs memory _swapPairs,
        address _stakingContract,
        uint256 _pid,
        address _timelock,
        StrategySettings memory _strategySettings
    )
        MasterChefStrategyForLP(
            _name,
            _depositToken,
            address(WAVAX), /*rewardToken=*/
            _poolRewardToken,
            _swapPairs,
            _stakingContract,
            _timelock,
            _pid,
            _strategySettings
        )
    {
        axialChef = IAxialChef(_stakingContract);
    }

    function _depositMasterchef(uint256 _pid, uint256 _amount) internal override {
        axialChef.deposit(_pid, _amount);
    }

    function _withdrawMasterchef(uint256 _pid, uint256 _amount) internal override {
        axialChef.withdraw(_pid, _amount);
    }

    function _emergencyWithdraw(uint256 _pid) internal override {
        axialChef.emergencyWithdraw(_pid);
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
        (uint256 pendingAxial, address bonusTokenAddress, , uint256 pendingBonusToken) = axialChef.pendingTokens(
            _pid,
            _user
        );
        return (pendingAxial, pendingBonusToken, bonusTokenAddress);
    }

    function _getRewards(uint256 _pid) internal override {
        axialChef.withdraw(_pid, 0);
    }

    function _getDepositBalance(uint256 pid, address user) internal view override returns (uint256 amount) {
        (amount, ) = axialChef.userInfo(pid, user);
    }

    function _getDepositFeeBips(
        uint256 /* pid */
    ) internal pure override returns (uint256) {
        return 0;
    }

    function _getWithdrawFeeBips(
        uint256 /* pid */
    ) internal pure override returns (uint256) {
        return 0;
    }

    function _bip() internal pure override returns (uint256) {
        return 10000;
    }
}
