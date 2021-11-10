// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

interface IBlizzChef {
    // Info of each user.
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }
    // Info of each pool.
    struct PoolInfo {
        uint256 totalSupply;
        uint256 allocPoint; // How many allocation points assigned to this pool.
        uint256 lastRewardTime; // Last second that reward distribution occurs.
        uint256 accRewardPerShare; // Accumulated rewards per share, times 1e12. See below.
        address onwardIncentives;
    }

    // Info about token emissions for a given time period.
    struct EmissionPoint {
        uint128 startTimeOffset;
        uint128 rewardsPerSecond;
    }

    function claimableReward(address account, address[] memory tokens) external view returns (uint256[] memory);

    function claim(address account, address[] memory tokens) external;

    function userInfo(address token, address user) external view returns (UserInfo memory);

    function poolInfo(address token) external view returns (PoolInfo memory);

    function totalAllocPoint() external view returns (uint256);

    function rewardsPerSecond() external view returns (uint256);

    function startTime() external view returns (uint256);
}
