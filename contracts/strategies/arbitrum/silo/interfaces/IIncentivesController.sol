// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IIncentivesController {
    function getRewardsBalance(address[] memory assets, address user) external view returns (uint256);
    function claimRewardsToSelf(address[] memory assets, uint256 amount) external;
}
