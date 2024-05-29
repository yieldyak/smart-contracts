// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IStargatePool {
    function token() external view returns (address);
    function deposit(address receiver, uint256 amount) external returns (uint256);
}
