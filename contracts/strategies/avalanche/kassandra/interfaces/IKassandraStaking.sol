// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IKassandraStaking {
    function withdraw(uint256 pid, uint256 amount) external;

    function stake(
        uint256 pid,
        uint256 amount,
        address stakeFor,
        address delegatee
    ) external;

    function earned(uint256 pid, address account) external view returns (uint256);

    function getReward(uint256 pid) external;

    function balanceOf(uint256 pid, address account) external view returns (uint256);

    function exit(uint256 pid) external;
}
