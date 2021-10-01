// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../../interfaces/IERC20.sol";

interface IBenqiAVAXDelegator is IERC20 {
    function exchangeRateStored() external view returns (uint256);
    function exchangeRateCurrent() external returns (uint);
    function mint() external payable;
    function redeem(uint256 redeemTokens) external returns (uint256);
    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);
    function borrow(uint256 borrowAmount) external returns (uint256);
    function repayBorrow() external payable;
    function balanceOfUnderlying(address owner) external returns (uint256);
    function borrowBalanceCurrent(address owner) external returns (uint256);
    function borrowBalanceStored(address owner) external view returns (uint256);
    function getAccountSnapshot(address account) external view returns (uint256 _error, uint256 _balance, uint256 _borrow, uint256 _mantissa);
    function getCash() external returns (uint);
}