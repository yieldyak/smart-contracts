// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IPendleGaugeController {
    struct MarketRewardData {
        uint128 pendlePerSec;
        uint128 accumulatedPendle;
        uint128 lastUpdated;
        uint128 incentiveEndsAt;
    }

    function rewardData(address market) external view returns (MarketRewardData memory);
    function pendle() external view returns (address);
}
