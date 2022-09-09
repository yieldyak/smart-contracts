// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IKassandraPool {
    function joinswapExternAmountIn(
        address tokenIn,
        uint256 tokenAmountIn,
        uint256 minPoolAmountOut
    ) external returns (uint256 poolAmountOut);
}
