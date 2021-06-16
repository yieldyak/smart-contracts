// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface IWAVAX {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
}