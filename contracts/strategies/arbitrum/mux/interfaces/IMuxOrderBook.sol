// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IMuxOrderBook {
    function placeLiquidityOrder(uint8 assetId, uint96 rawAmount, bool isAdding) external;
}
