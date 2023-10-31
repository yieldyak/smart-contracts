// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IUnitroller {
    function enterMarkets(address[] memory cTokens) external returns (uint256[] memory);

    function exitMarket(address cTokenAddress) external returns (uint256);

    function mintAllowed(address cToken, address minter, uint256 mintAmount) external returns (uint256);

    function redeemAllowed(address cToken, address redeemer, uint256 redeemTokens) external returns (uint256);

    function borrowAllowed(address cToken, address borrower, uint256 borrowAmount) external returns (uint256);

    function claimComp(address holder) external;

    function claimComp(address holder, address[] memory qiTokens) external;

    function compAccrued(address holder) external view returns (uint256);

    function markets(address cTokenAddress) external view returns (bool, uint256);

    function compSupplyState(address holder) external view returns (uint224 index, uint32 block);

    function compSupplySpeeds(address qiToken) external view returns (uint256);

    function compBorrowSpeeds(address qiToken) external view returns (uint256);

    function compBorrowState(address holder) external view returns (uint224 index, uint32 block);

    function compSupplierIndex(address qiContractAddress, address holder)
        external
        view
        returns (uint256 supplierIndex);

    function compBorrowerIndex(address qiContractAddress, address holder)
        external
        view
        returns (uint256 borrowerIndex);

    function getCompAddress() external view returns (address);

    function getBlockNumber() external view returns (uint256);
}
