// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface ICycleRewards {
    function earned(address account) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function getReward() external;
}
