// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IMuxRewardTracker {
    function claimableReward(address _account) external view returns (uint256);
}
