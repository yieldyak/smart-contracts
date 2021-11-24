
// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

interface IBenqiUnitroller {
    function enterMarkets(address[] memory cTokens) external returns (uint[] memory);
    function exitMarket(address cTokenAddress) external returns (uint);
    function mintAllowed(address cToken, address minter, uint mintAmount) external returns (uint);
    function redeemAllowed(address cToken, address redeemer, uint redeemTokens) external returns (uint);
    function borrowAllowed(address cToken, address borrower, uint borrowAmount) external returns (uint);
    function claimReward(uint8 rewardType, address holder) external; //reward type 0 is qi, 1 is avax
    function rewardAccrued(uint8 rewardType, address holder) external view returns (uint);
    function markets(address cTokenAddress) external view returns (bool, uint);
    function getClaimableRewards(uint rewardToken) external view returns (uint, uint);
    function rewardSupplyState(uint8 rewardType, address holder) external view returns (uint224 index, uint32 timestamp);
    function rewardBorrowState(uint8 rewardType, address holder) external view returns (uint224 index, uint32 timestamp);
    function rewardSupplierIndex(uint8 rewardType, address qiContractAddress, address holder) external view returns (uint supplierIndex);
    function rewardBorrowerIndex(uint8 rewardType, address qiContractAddress, address holder) external view returns (uint borrowerIndex);
}