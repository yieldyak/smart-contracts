// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

interface IMoreMoneyStakingRewards {
    function stake(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function withdrawVestedReward() external;

    function balanceOf(address account) external view returns (uint256);

    function rewardPerToken() external view returns (uint256);

    function vestingPeriod() external view returns (uint256);

    function userRewardPerTokenAccountedFor(address account) external view returns (uint256);

    function vestingStart(address account) external view returns (uint256);

    function rewards(address account) external view returns (uint256);

    function exit() external;
}
