// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface IGondolaChef {
    function gondola() external view returns (address);

    function gondolaPerSec() external view returns (uint256);

    function totalAllocPoint() external view returns (uint256);

    function startAt() external view returns (uint256);

    function poolLength() external view returns (uint256);

    function add(
        uint256 _allocPoint,
        address _lpToken,
        bool _withUpdate
    ) external;

    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) external;

    function getMultiplier(uint256 _from, uint256 _to) external view returns (uint256);

    function pendingGondola(uint256 _pid, address _user) external view returns (uint256);

    function massUpdatePools() external;

    function updatePool(uint256 _pid) external;

    function deposit(uint256 _pid, uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function emergencyWithdraw(uint256 _pid) external;

    function poolInfo(uint256 pid)
        external
        view
        returns (
            address lpToken,
            uint256 allocPoint,
            uint256 lastRewardAt,
            uint256 accGondolaPerShare
        );

    function userInfo(uint256 pid, address user) external view returns (uint256 amount, uint256 rewardDebt);

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
}
