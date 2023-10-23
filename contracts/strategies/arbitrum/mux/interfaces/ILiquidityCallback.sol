// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface ILiquidityCallback {
    struct LiquidityOrder {
        uint64 id;
        address account;
        uint96 rawAmount; // erc20.decimals
        uint8 assetId;
        bool isAdding;
        uint32 placeOrderTime; // 1e0
    }

    function beforeFillLiquidityOrder(
        LiquidityOrder calldata order,
        uint96 assetPrice,
        uint96 mlpPrice,
        uint96 currentAssetValue,
        uint96 targetAssetValue
    ) external returns (bool);

    function afterFillLiquidityOrder(
        LiquidityOrder calldata order,
        uint256 outAmount,
        uint96 assetPrice,
        uint96 mlpPrice,
        uint96 currentAssetValue,
        uint96 targetAssetValue
    ) external;

    function afterCancelLiquidityOrder(LiquidityOrder calldata order) external;
}
