// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IDepositHelper {
    function depositMarket(address market, uint256 amount) external;
    function withdrawMarket(address market, uint256 amount) external;
    function pendleStaking() external view returns (address);
}
