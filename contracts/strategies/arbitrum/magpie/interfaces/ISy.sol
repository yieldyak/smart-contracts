// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface ISy {
    function previewDeposit(address tokenIn, uint256 amount) external view returns (uint256);
}
