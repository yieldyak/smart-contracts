// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IPendleRouter {
    struct TokenInput {
        // Token/Sy data
        address tokenIn;
        uint256 netTokenIn;
        address tokenMintSy;
        address bulk;
        // aggregator data
        address pendleSwap;
        SwapData swapData;
    }

    struct SwapData {
        SwapType swapType;
        address extRouter;
        bytes extCalldata;
        bool needScale;
    }

    enum SwapType {
        NONE,
        KYBERSWAP,
        ONE_INCH,
        // ETH_WETH not used in Aggregator
        ETH_WETH
    }

    struct ApproxParams {
        uint256 guessMin;
        uint256 guessMax;
        uint256 guessOffchain; // pass 0 iMn to skip this variable
        uint256 maxIteration; // every iteration, the diff between guessMin and guessMax will be divided by 2
        uint256 eps; // the max eps between the returned result & the correct result, base 1e18. Normally this number will be set
            // to 1e15 (1e18/1000 = 0.1%)
    }

    function mintSyFromToken(address receiver, address SY, uint256 minSyOut, TokenInput calldata input)
        external
        payable
        returns (uint256 netSyOut);

    function addLiquiditySingleSy(
        address receiver,
        address market,
        uint256 netSyIn,
        uint256 minLpOut,
        ApproxParams calldata guessPtReceivedFromSy
    ) external returns (uint256 netLpOut, uint256 netSyFee);
}
