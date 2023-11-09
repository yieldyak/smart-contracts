// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface ISiloLens {
    function getDepositAmount(address _silo, address _asset, address _user, uint256 _timestamp)
        external
        view
        returns (uint256 totalUserDeposits);
    function getBorrowAmount(address _silo, address _asset, address _user, uint256 _timestamp)
        external
        view
        returns (uint256 totalUserBorrows);
    function getUserMaximumLTV(address _silo, address _user) external returns (uint256);
    function calculateCollateralValue(address _silo, address _user, address _asset) external returns (uint256);
}
