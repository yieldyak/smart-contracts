// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IJoeStaking {
    function getDeposit(address account) external view returns (uint256);
    function getPendingReward(address account) external view returns (address, uint256);
    function stake(uint256 amount) external;
    function unstake(uint256 amount) external;
    function claim() external;
}
