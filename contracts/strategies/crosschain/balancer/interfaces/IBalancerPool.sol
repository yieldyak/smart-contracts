// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IBalancerPool {
    function getPoolId() external view returns (bytes32);
    function getBptIndex() external view returns (uint256);
}
