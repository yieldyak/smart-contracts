// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IGauge {
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function withdrawAll() external;
    function earned(address account) external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function getReward() external;
}
