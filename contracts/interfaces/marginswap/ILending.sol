// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface ILending {
    function withdrawIncentive(address token) external;

    function buyHourlyBondSubscription(address issuer, uint256 amount) external;

    function closeHourlyBondAccount(address issuer) external;

    function withdrawHourlyBond(address issuer, uint256 amount) external;

    function viewHourlyBondAmount(address issuer, address holder) external view returns (uint256);

    function lendingMeta(address token)
        external
        view
        returns (
            uint256 totalLending,
            uint256 totalBorrowed,
            uint256 lendingCap,
            uint256 cumulIncentiveAllocationFP,
            uint256 incentiveLastUpdated,
            uint256 incentiveEnd,
            uint256 incentiveTarget
        );

    function hourlyBondAccounts(address token, address holder)
        external
        view
        returns (
            uint256 amount,
            uint256 yieldQuotientFP,
            uint256 moduloHour,
            uint256 incentiveAllocationStart
        );
}
