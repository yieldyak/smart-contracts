// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

interface IVeEcdRewardPool {
    function earned(address account) external view returns (uint256);

    function getReward(address _account) external returns (bool);

    function queueNewRewards(uint256 _rewards) external returns (bool);
}
