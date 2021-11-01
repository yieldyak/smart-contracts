// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

// This interface should work for both LP and ORCA staking.
// https://github.com/UrsaMaritimus/orca/blob/main/apps/avai/src/contracts/PodLeader.sol
// https://github.com/UrsaMaritimus/orca/blob/main/apps/avai/src/contracts/OrcaStaking.sol
interface IAvaiPodLeader {
    function poolLength() external view returns (uint256);

    function deposit(uint256 pid, uint256 amount) external;

    function withdraw(uint256 pid, uint256 amount) external;

    function pendingRewards(uint256 pid, address account) external view returns (uint256);

    function emergencyWithdraw(uint256 pid) external;

    function userInfo(uint256 pid, address user) external view returns (uint256 amount, uint256 rewardDebt);
}
