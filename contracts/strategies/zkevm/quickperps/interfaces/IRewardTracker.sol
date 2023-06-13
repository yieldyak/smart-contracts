// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IRewardTracker {
    function stakedAmounts(address _account) external view returns (uint256);

    function claimable(address _account) external view returns (uint256);
}
