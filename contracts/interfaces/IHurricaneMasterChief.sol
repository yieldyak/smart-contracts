// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface IHurricaneMasterChief {
    function pending(uint256 pid, address user) external view returns (uint256, uint256);

    function deposit(uint256 pid, uint256 amount) external;

    function withdraw(uint256 pid, uint256 amount) external;

    function emergencyWithdraw(uint256 pid) external;

    function userInfo(uint256 _pid, address _address) external view returns (uint256, uint256, uint256);

    function LpOfPid(address _address) external view returns(uint256);
}