// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface IElevenChef {
    function userInfo(uint256 pid, address user) external view returns (uint256 amount, uint256 rewardDebt);

    function poolInfo(uint256 pid)
        external
        view
        returns (
            address lpToken,
            uint256 allocPoint,
            uint256 lastRewardTime,
            uint256 accElevenPerShare
        );

    function poolLength() external view returns (uint256);

    function getMultiplier(uint256 _from, uint256 _to) external pure returns (uint256);

    function pendingEleven(uint256 _pid, address _user) external view returns (uint256);

    function massUpdatePools() external;

    function updatePool(uint256 _pid) external;

    function deposit(uint256 _pid, uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function emergencyWithdraw(uint256 _pid) external;
}
