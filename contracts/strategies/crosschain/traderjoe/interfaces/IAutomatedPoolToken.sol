// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IAutomatedPoolToken {
    function getTokenX() external view returns (address);
    function getTokenY() external view returns (address);
    function deposit(uint256 amountX, uint256 amountY)
        external
        returns (uint256 shares, uint256 effectiveX, uint256 effectiveY);
}
