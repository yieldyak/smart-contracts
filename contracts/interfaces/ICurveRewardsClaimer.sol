pragma experimental ABIEncoderV2;
// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

library DataTypes {
    struct RewardToken {
        address distributor;
        uint256 period_finish;
        uint256 rate;
        uint256 duration;
        uint256 received;
        uint256 paid;
    }
}

interface ICurveRewardsClaimer {
    function reward_data(address reward) external view returns (DataTypes.RewardToken memory);

    function last_update_time() external view returns (uint256);

    function get_reward() external;
}
