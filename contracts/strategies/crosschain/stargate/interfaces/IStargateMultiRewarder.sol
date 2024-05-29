// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IStargateMultiRewarder {
    function getRewards(address token, address user) external view returns (address[] memory, uint256[] memory);
}
