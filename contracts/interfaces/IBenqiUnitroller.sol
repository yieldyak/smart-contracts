// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface IBenqiUnitroller {
    function enterMarkets(address[] memory cTokens) external returns (uint256[] memory);

    function exitMarket(address cTokenAddress) external returns (uint256);

    function mintAllowed(
        address cToken,
        address minter,
        uint256 mintAmount
    ) external returns (uint256);

    function redeemAllowed(
        address cToken,
        address redeemer,
        uint256 redeemTokens
    ) external returns (uint256);

    function borrowAllowed(
        address cToken,
        address borrower,
        uint256 borrowAmount
    ) external returns (uint256);

    function claimReward(uint8 rewardType, address holder) external; //reward type 0 is qi, 1 is avax

    function rewardAccrued(uint8 rewardType, address holder) external view returns (uint256);

    function markets(address cTokenAddress) external view returns (bool, uint256);

    function getClaimableRewards(uint256 rewardToken) external view returns (uint256, uint256);

    function rewardSupplyState(uint8 rewardType, address holder)
        external
        view
        returns (uint224 index, uint32 timestamp);

    function rewardBorrowState(uint8 rewardType, address holder)
        external
        view
        returns (uint224 index, uint32 timestamp);

    function rewardSupplierIndex(
        uint8 rewardType,
        address qiContractAddress,
        address holder
    ) external view returns (uint256 supplierIndex);

    function rewardBorrowerIndex(
        uint8 rewardType,
        address qiContractAddress,
        address holder
    ) external view returns (uint256 borrowerIndex);
}
