// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IWombatAsset {
    function pool() external view returns (address);
    function underlyingToken() external view returns (address);
}
