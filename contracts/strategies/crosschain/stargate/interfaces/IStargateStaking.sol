// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IStargateStaking {
    function deposit(address token, uint256 amount) external;
    function withdraw(address token, uint256 amount) external;
    function claim(address[] memory) external;
    function emergencyWithdraw(address token) external;
    function balanceOf(address token, address user) external view returns (uint256);
    function rewarder(address token) external view returns (address);
}
