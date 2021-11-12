// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface IAxialSwap {
    function calculateTokenAmount(
        address account,
        uint256[] calldata amounts,
        bool deposit
    ) external view returns (uint256);

    function addLiquidity(
        uint256[] calldata amounts,
        uint256 minToMint,
        uint256 deadline
    ) external returns (uint256);

    function getTokenIndex(address tokenAddress) external view returns (uint8);
}
