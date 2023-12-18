// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IMultiRewards {
    function balanceOf(address account) external view returns (uint256);
    function rewardTokens(uint256 index) external view returns (address);
    function earned(address account, address reward) external view returns (uint256);
    function getReward() external;
    function stake(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function exit() external;
}
