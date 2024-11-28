// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface ITMStaking {
    function claimRewards(address token, address to) external returns (uint256);
    function deposit(address token, address to, uint256 amount, uint256 minAmount)
        external
        returns (uint256 actualAmount);
    function getPendingRewards(address token, address account) external view returns (uint256 pending);
    function getStakeOf(address token, address account) external view returns (uint256 amount, uint256 lockedAmount);
    function withdraw(address token, address to, uint256 amount) external returns (uint256);
}
