// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IGauge {
    function deposit(uint256 amount) external returns (uint256 _tokenId);
    function _depositEpoch(uint256 tokenId) external view returns (uint256);
    function withdrawAndHarvest(uint256 tokenId) external;
    function withdrawAndHarvestAll() external;
    function harvestAndMerge(uint256 _from, uint256 _to) external;
    function harvestAndSplit(uint256[] memory amounts, uint256 _tokenId) external;
    function maNFTs() external view returns (address);
    function earned(address account) external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function balanceOfToken(uint256 tokenId) external view returns (uint256);
    function getAllReward() external;
}
