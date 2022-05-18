// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface ICurveRewardsGaugeReadOnly {
    function claimable_reward_write(address user, address token) external view returns (uint256);
}
