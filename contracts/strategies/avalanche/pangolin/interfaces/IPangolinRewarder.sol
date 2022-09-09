// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IPangolinRewarder {
    function pendingTokens(
        uint256,
        address,
        uint256 rewardAmount
    ) external view returns (address[] memory rewardTokens, uint256[] memory rewardAmounts);
}
