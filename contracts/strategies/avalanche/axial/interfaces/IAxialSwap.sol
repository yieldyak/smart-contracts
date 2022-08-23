// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IAxialSwap {
    /**
     * @dev Assumes amounts to be 18 decimals. Use token with 18 decimals to addLiquidity or convert amount before!
     */
    function addLiquidity(
        uint256[] calldata amounts,
        uint256 minToMint,
        uint256 deadline
    ) external returns (uint256);

    function getTokenIndex(address tokenAddress) external view returns (uint8);
}
