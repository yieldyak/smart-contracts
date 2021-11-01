// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface ICurveRewardsGaugeReadOnly {
    function claimable_reward_write(address user, address token) external view returns (uint256);
}
