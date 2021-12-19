// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

interface ICurveRewardsGaugeReadOnly {
    function claimable_reward_write(address user, address token) external view returns(uint);
}