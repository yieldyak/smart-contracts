// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface ILiquidityManager {
    function calculateReturns() external;

    function distributeTokens() external;

    function vestAllocation() external;

    function calculateAndDistribute() external;
}
