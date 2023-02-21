// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface INitroPool {
    function withdraw(uint256 positionId) external;

    function pendingRewards(address account) external view returns (uint256 pending1, uint256 pending2);

    function rewardsToken1() external view returns (address);

    function rewardsToken2() external view returns (address);

    function harvest() external;

    function nftPool() external view returns (address);
}
