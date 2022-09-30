// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IMasterChefWoo {
    function userInfo(uint256 pid, address account) external view returns (uint256 amount, uint256 rewardDebt);

    function poolInfo(uint256 pid)
        external
        view
        returns (
            address weToken,
            uint256 allocPoint,
            uint256 lastRewardBlock,
            uint256 accTokenPerShare,
            address rewarder
        );

    function xWoo() external view returns (address);

    function pendingXWoo(uint256 pid, address user) external view returns (uint256, uint256);

    function deposit(uint256 pid, uint256 amount) external;

    function withdraw(uint256 pid, uint256 amount) external;

    function harvest(uint256 pid) external;

    function emergencyWithdraw(uint256 pid) external;
}
