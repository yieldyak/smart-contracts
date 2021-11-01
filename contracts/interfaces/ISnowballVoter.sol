// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface ISnowballVoter {
    function execute(
        address to,
        uint256 value,
        bytes calldata data
    ) external returns (bool, bytes memory);

    function increaseAmount(uint256) external;
}
