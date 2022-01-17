// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

interface IStakeDaoRewarder {
    function balanceOf(address account) external view returns (uint256);

    function stake(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function getReward() external;

    function earned(address account, address _rewardsToken) external view returns (uint256);

    function exit() external;
}
