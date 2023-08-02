// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../../MasterChefStrategyForLP.sol";

import "./interfaces/IKassandraStaking.sol";

contract KassandraStrategyForLP is MasterChefStrategyForLP {
    using SafeMath for uint256;

    IWGAS private constant WAVAX = IWGAS(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);

    IKassandraStaking public stakingContract;

    constructor(
        string memory _name,
        address _poolRewardToken,
        SwapPairs memory _swapPairs,
        address _stakingContract,
        uint256 _pid,
        address _timelock,
        StrategySettings memory _strategySettings
    ) MasterChefStrategyForLP(_name, _poolRewardToken, _swapPairs, _timelock, _pid, _strategySettings) {
        stakingContract = IKassandraStaking(_stakingContract);
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

    function _depositMasterchef(uint256 _pid, uint256 _amount) internal override {
        depositToken.approve(address(stakingContract), _amount);
        stakingContract.stake(_pid, _amount, address(this), address(this));
    }

    function _withdrawMasterchef(uint256 _pid, uint256 _amount) internal override {
        stakingContract.withdraw(_pid, _amount);
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
        uint256 pendingReward = stakingContract.earned(_pid, address(_user));
        return (pendingReward, 0, address(0));
    }

    function _getRewards(uint256 _pid) internal override {
        stakingContract.getReward(_pid);
    }

    function _getDepositBalance(uint256 pid, address user) internal view override returns (uint256 amount) {
        return stakingContract.balanceOf(pid, user);
    }

    function _bip() internal pure override returns (uint256) {
        return 10000;
    }

    function _emergencyWithdraw(uint256 _pid) internal override {
        depositToken.approve(address(stakingContract), 0);
        stakingContract.exit(_pid);
    }
}
