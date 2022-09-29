// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IWooSuperChargerVault {
    function getPricePerFullShare() external view returns (uint256);

    function want() external view returns (address);

    function deposit(uint256 amount) external payable;
}
