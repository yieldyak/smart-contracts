// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./IGmxDepositor.sol";

interface IGmxProxy {
    function gmxDepositor() external view returns (IGmxDepositor);

    function gmxRewardRouter() external view returns (address);

    function buyAndStakeGlp(uint256 _amount) external returns (uint256);

    function withdrawGlp(uint256 _amount) external;

    function pendingRewards() external view returns (uint256);

    function claimReward() external;

    function totalDeposits() external view returns (uint256);
}
