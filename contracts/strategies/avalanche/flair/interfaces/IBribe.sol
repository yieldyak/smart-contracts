// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IBribe {
    function getReward(uint256 tokenId, address[] memory tokens) external;
    function rewardTokensLength() external view returns (uint256);
    function rewardTokens(uint256 index) external view returns (address);
}
