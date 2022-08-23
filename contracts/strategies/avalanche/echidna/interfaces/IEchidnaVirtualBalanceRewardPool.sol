// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IEchidnaVirtualBalanceRewardPool {
    function stake(address, uint256) external returns (bool);

    function withdraw(address, uint256) external returns (bool);

    function getReward(address) external returns (bool);

    function queueNewRewards(uint256) external returns (bool);

    function rewardToken() external view returns (address);

    function earned(address account) external view returns (uint256);

    function initialize(address deposit_, address reward_) external;
}
