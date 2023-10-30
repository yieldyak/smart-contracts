// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IDistributor {
    function pendingMlpRewards() external view returns (uint256);
}
