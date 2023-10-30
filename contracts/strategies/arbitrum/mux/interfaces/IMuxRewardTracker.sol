// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IMuxRewardTracker {
    function claimableReward(address _account) external view returns (uint256);
    function lastRewardBalance() external view returns (uint256);
    function distributor() external view returns (address);
    function totalSupply() external view returns (uint256);
    function cumulativeRewardPerToken() external view returns (uint256);
    function stakedAmounts(address account) external view returns (uint256);
    function previousCumulatedRewardPerToken(address account) external view returns (uint256);
}
