// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface IChef {
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function emergencyWithdraw(uint256 _pid) external;
}