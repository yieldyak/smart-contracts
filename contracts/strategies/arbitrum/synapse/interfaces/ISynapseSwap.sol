// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface ISynapseSwap {
    function addLiquidity(uint256[] calldata amounts, uint256 minToMint, uint256 deadline) external returns (uint256);

    function getTokenIndex(address token) external view returns (uint8);
}
