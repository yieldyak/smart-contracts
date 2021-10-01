// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISnowballVoter {
    function execute(
        address to,
        uint value,
        bytes calldata data
    ) external returns (bool, bytes memory);

    function increaseAmount(uint) external;
}
