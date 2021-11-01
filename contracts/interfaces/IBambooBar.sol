// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface IBambooBar {
    function enter(uint256 _amount) external;

    function leave(uint256 _share) external;

    function bamboo() external view returns (address);
}
