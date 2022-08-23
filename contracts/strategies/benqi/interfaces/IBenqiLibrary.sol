// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IBenqiLibrary {
    function calculateReward(
        address rewardController,
        address tokenDelegator,
        uint8 tokenIndex,
        address account
    ) external view returns (uint256);
}
