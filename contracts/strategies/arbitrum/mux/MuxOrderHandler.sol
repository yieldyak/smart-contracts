// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./../../../interfaces/IERC20.sol";
import "./../../../interfaces/IWETH.sol";
import "./../../../lib/SafeERC20.sol";
import "./interfaces/ILiquidityCallback.sol";
import "./interfaces/IMuxProxy.sol";
import "./interfaces/IMuxOrderBook.sol";

contract MuxOrderHandler is ILiquidityCallback {
    using SafeERC20 for IERC20;

    error OnlyOrderBook();
    error OnlyProxy();
    error OnlyDev();
    error InvalidUpdate();

    address internal constant MLP = 0x7CbaF5a14D953fF896E5B3312031515c858737C8;
    address internal constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    address immutable muxDepositor;
    IMuxOrderBook immutable orderBook;
    uint8 immutable assetId;

    address public devAddr;
    uint256 public largeOrderThreshold;
    IMuxProxy public proxy;
    uint256 public pendingOrderId;

    constructor(
        address _proxy,
        address _muxDepositor,
        address _orderBook,
        uint8 _assetId,
        uint256 _largeOrderThreshold,
        address _devAddr
    ) {
        proxy = IMuxProxy(_proxy);
        muxDepositor = _muxDepositor;
        orderBook = IMuxOrderBook(_orderBook);
        assetId = _assetId;
        largeOrderThreshold = _largeOrderThreshold;
        devAddr = _devAddr;
    }

    receive() external payable {
        require(msg.sender == address(WETH), "not allowed");
    }

    function orderMlp(uint256 _amount) external {
        if (msg.sender != address(proxy)) {
            revert OnlyProxy();
        }
        if (_amount > largeOrderThreshold) {
            pendingOrderId = orderBook.nextOrderId();
        }
        IWETH(WETH).withdraw(_amount);
        orderBook.placeLiquidityOrder{value: _amount}(assetId, uint96(_amount), true);
    }

    function largePendingOrder() external view returns (bool) {
        return pendingOrderId > 0;
    }

    function afterFillLiquidityOrder(LiquidityOrder calldata order, uint256 outAmount, uint96, uint96, uint96, uint96)
        external
        override
    {
        if (msg.sender != address(orderBook)) {
            revert OnlyOrderBook();
        }
        if (pendingOrderId == order.id) {
            pendingOrderId = 0;
        }
        IERC20(MLP).safeTransfer(muxDepositor, outAmount);
        proxy.stakeMlp(outAmount);
    }

    function afterCancelLiquidityOrder(LiquidityOrder calldata order) external override {
        if (msg.sender != address(orderBook)) {
            revert OnlyOrderBook();
        }
        if (pendingOrderId == order.id) {
            pendingOrderId = 0;
        }
    }

    function beforeFillLiquidityOrder(LiquidityOrder calldata, uint96, uint96, uint96, uint96)
        external
        override
        returns (bool)
    {}

    function updateLargeOrderThreshold(uint256 _largeOrderThreshold) public {
        if (msg.sender != devAddr) {
            revert OnlyDev();
        }
        largeOrderThreshold = _largeOrderThreshold;
    }

    function updateProxy(address _newValue) public {
        if (msg.sender != devAddr) {
            revert OnlyDev();
        }
        proxy = IMuxProxy(_newValue);
    }

    function updateDevAddr(address _newValue) public {
        if (msg.sender != devAddr) {
            revert OnlyDev();
        }
        if (_newValue == address(0)) {
            revert InvalidUpdate();
        }
        devAddr = _newValue;
    }
}
