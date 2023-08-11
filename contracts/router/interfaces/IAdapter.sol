// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAdapter {
    function swap(uint256 amountIn, uint256 amountOut, address fromToken, address toToken, address to) external;

    function query(uint256 amountIn, address tokenIn, address tokenOut) external view returns (uint256);
}
