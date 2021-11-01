// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface IYakChef {
    function poolLength() external view returns (uint256);

    function pendingRewards(uint256 pid, address account) external view returns (uint256);

    function deposit(uint256 pid, uint256 amount) external;

    function withdraw(uint256 pid, uint256 amount) external;

    function emergencyWithdraw(uint256 _pid) external;

    function poolInfo(uint256 pid)
        external
        view
        returns (
            address token,
            uint256 allocPoint,
            uint256 lastRewardTimestamp,
            uint256 accRewardsPerShare,
            uint256 totalStaked,
            bool vpForDeposit
        );

    function userInfo(uint256 pid, address user) external view returns (uint256 amount, uint256 rewardDebt);
}
