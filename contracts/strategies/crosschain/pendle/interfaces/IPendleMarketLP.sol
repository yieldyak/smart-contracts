// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IPendleMarketLP {
    function readTokens() external view returns (address sy, address pt, address yt);
    function userReward(address token, address user) external view returns (uint128 userIndex, uint128 rewardAccrued);
    function totalActiveSupply() external view returns (uint256);
    function activeBalance(address user) external view returns (uint256);
    function rewardState(address token) external view returns (uint128 index, uint128 lastBalance);
    function getRewardTokens() external view returns (address[] memory);
    function redeemRewards(address user) external;
}
