// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IPendleStaticRouter {
    function addLiquiditySingleSyStatic(address market, uint256 netSyIn)
        external
        view
        returns (
            uint256 netLpOut,
            uint256 netPtFromSwap,
            uint256 netSyFee,
            uint256 priceImpact,
            uint256 exchangeRateAfter,
            // extra-info
            uint256 netSyToSwap
        );
}
