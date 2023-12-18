// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IVault {
    function liquidityPool() external view returns (address);
    function orderBook() external view returns (address);
}
