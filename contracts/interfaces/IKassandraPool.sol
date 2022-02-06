// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

interface IKassandraPool {
    function joinswapExternAmountIn(
        address tokenIn,
        uint256 tokenAmountIn,
        uint256 minPoolAmountOut
    ) external returns (uint256 poolAmountOut);
}
