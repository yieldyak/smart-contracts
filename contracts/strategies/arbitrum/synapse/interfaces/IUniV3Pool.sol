// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IUniV3Pool {
    function token0() external pure returns (address);
    function token1() external pure returns (address);
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);
}
