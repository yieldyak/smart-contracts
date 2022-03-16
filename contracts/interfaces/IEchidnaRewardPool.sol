// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

interface IEchidnaRewardPool {
    function balanceOf(address _account) external view returns (uint256);

    function getReward(address _account, bool _claimExtras) external returns (bool);

    function stake(address _account, uint256 _amount) external returns (bool);

    function unStake(
        address _account,
        uint256 _amount,
        bool _claim
    ) external returns (bool);

    function earned(address _account) external view returns (uint256);

    function extraRewardsLength() external view returns (uint256);

    function extraRewards(uint256 index) external view returns (address);

    function rewardToken() external view returns (address);
}
