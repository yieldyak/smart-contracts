// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IMuxDepositor {
    function execute(address to, uint256 value, bytes calldata data) external returns (bool, bytes memory);

    function setMuxProxy(address _proxy) external;
}
