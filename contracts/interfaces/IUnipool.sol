// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface IUnipool {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function earned(address account) external view returns (uint256);

    function stake(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function claimReward() external;

    function withdrawAndClaim() external;
}
