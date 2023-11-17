// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface ISwap {
    function addLiquidity(uint256[] memory amounts, uint256 minToMint, uint256 deadline) external returns (uint256);
    function getTokenIndex(address reward) external view returns (uint256);
}
