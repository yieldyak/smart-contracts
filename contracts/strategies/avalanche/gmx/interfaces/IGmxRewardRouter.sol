// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IGmxRewardRouter {
    function extendedGmxTracker() external view returns (address);
    function feeGlpTracker() external view returns (address);
}
