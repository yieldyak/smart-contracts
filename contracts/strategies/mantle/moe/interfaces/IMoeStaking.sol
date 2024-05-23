// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IMoeStaking {
    function getSMoe() external view returns (address);
    function getDeposit(address user) external view returns (uint256);
    function stake(uint256 amount) external;
    function unstake(uint256 amount) external;
    function claim() external;
}
