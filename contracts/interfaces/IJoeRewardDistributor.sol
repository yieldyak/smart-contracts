// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

// https://github.com/traderjoe-xyz/joe-lending/blob/main/contracts/RewardDistributor.sol
interface IJoeRewardDistributor {

    struct RewardMarketState {
        uint224 index;
        uint32 timestamp;
    }

    // rewardType  0 = JOE, 1 = AVAX
    function rewardSupplyState(uint8 rewardType, address holder) external view returns (RewardMarketState memory);
    function rewardBorrowState(uint8 rewardType, address holder) external view returns (RewardMarketState memory);
    function rewardSupplierIndex(uint8 rewardType, address contractAddress, address holder) external view returns (uint supplierIndex);
    function rewardBorrowerIndex(uint8 rewardType, address contractAddress, address holder) external view returns (uint borrowerIndex);
    function rewardAccrued(uint8, address) external view returns (uint256);
    function claimReward(uint8 rewardType, address payable holder) external;
}