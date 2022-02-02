// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface IPangolinRewarder {
    function pendingTokens(
        uint256,
        address,
        uint256 rewardAmount
    ) external view returns (address[] memory rewardTokens, uint256[] memory rewardAmounts);
}
