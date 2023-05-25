// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IWombatAsset {
    function pool() external view returns (address);
    function liability() external view returns (uint120);
    function totalSupply() external view returns (uint256);
}
