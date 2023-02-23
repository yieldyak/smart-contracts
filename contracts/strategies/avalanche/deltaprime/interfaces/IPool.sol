// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IPool {
    function deposit(uint256 _amount) external;

    function depositNativeToken() external payable;

    function withdrawNativeToken(uint256 _amount) external;

    function withdraw(uint256 _amount) external;

    function checkRewards() external view returns (uint256);

    function getRewards() external;

    function balanceOf(address user) external view returns (uint256);

    function poolRewarder() external view returns (address);
}
