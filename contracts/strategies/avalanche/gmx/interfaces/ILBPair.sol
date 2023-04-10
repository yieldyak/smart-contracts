// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

interface ILBPair {
    function swap(bool _swapForY, address _to) external returns (uint256 amountXOut, uint256 amountYOut);
}
