// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

interface IDragonChef {
    struct PoolInfo {
        address lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. DCAUs to distribute per block. 100 - 1point
        uint256 lastRewardTime; // Last block timestamp that DCAUs distribution occurs.
        uint256 accDCAUPerShare; // Accumulated DCAUs per share, times 1e12. See below.
        uint16 depositFeeBP; // Deposit fee in basis points 10000 - 100%
        uint256 lpSupply;
    }

    function poolInfo(uint256 pid) external view returns (PoolInfo memory);

    function deposit(uint256 pid, uint256 amount) external;

    function withdraw(uint256 pid, uint256 amount) external;

    function pendingDcau(uint256 pid, address account) external view returns (uint256);

    function emergencyWithdraw(uint256 pid) external;

    function userInfo(uint256 pid, address user) external view returns (uint256 amount, uint256 rewardDebt);
}
