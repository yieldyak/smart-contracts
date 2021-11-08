// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface IBlizzChef {
    function claimableReward(address account, address[] memory tokens) external view returns (uint256[] memory);

    function claim(address account, address[] memory tokens) external;
}
