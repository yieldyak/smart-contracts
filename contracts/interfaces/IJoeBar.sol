// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface IJoeBar {
    function enter(uint256 _amount) external;

    function leave(uint256 _share) external;

    function balanceOf(address account) external returns (uint256);
}
