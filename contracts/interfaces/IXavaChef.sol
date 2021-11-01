// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface IXavaChef {
    function erc20() external view returns (address);

    function paidOut() external view returns (uint256);

    function rewardPerSecond() external view returns (uint256);

    function totalAllocPoint() external view returns (uint256);

    function startTimestamp() external view returns (uint256);

    function endTimestamp() external view returns (uint256);

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

    function deposited(uint256 _pid, address _user) external view returns (uint256);

    function pending(uint256 _pid, address _user) external view returns (uint256);

    function totalPending() external view returns (uint256);

    function massUpdatePools() external;

    function updatePool(uint256 _pid) external;

    function fund(uint256 _amount) external;

    function deposit(uint256 _pid, uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function emergencyWithdraw(uint256 _pid) external;

    function poolInfo(uint256 pid)
        external
        view
        returns (
            address lpToken,
            uint256 allocPoint,
            uint256 lastRewardTimestamp,
            uint256 accERC20PerShare,
            uint256 totalDeposits
        );

    function userInfo(uint256 pid, address user) external view returns (uint256 amount, uint256 rewardDebt);

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
}
