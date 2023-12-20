// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./IMuxDepositor.sol";

interface IMuxProxy {
    function muxDepositor() external view returns (IMuxDepositor);

    function muxRewardRouter() external view returns (address);

    function orderMlp(uint256 _amount) external;

    function stakeMlp(uint256 _amount) external;

    function withdrawMlp(uint256 _amount) external;

    function pendingRewards() external view returns (uint256);

    function claimReward() external;

    function totalDeposits() external view returns (uint256);

    function largePendingOrder() external view returns (bool);
}
