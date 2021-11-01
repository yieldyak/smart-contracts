// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface ILQTYStaking {
    function getPendingETHGain(address _user) external view returns (uint256);

    function getPendingLUSDGain(address _user) external view returns (uint256);

    function snapshots(address) external view returns (uint256);

    function stakes(address) external view returns (uint256);

    function stake(uint256) external;

    function unstake(uint256) external;
}
