// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface IProxy {
    function execute(
        address to,
        uint value,
        bytes calldata data
    ) external returns (bool, bytes memory);

    function increaseAmount(uint) external;
    function createLock(uint _value, uint _unlockTime) external;
}
