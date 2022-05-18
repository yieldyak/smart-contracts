// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IKyberRewardLockerV2 {
    function vestCompletedSchedulesForMultipleTokens(address[] calldata tokens)
        external
        returns (uint256[] memory vestedAmounts);
}
