// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IGmxRewardTracker {
    function rewardToken() external view returns (address);
    function claim(address receiver) external returns (uint256);
    function stakedAmounts(address account) external view returns (uint256);
}
