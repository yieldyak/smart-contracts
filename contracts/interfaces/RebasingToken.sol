// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

interface RebasingToken {
    function circulatingSupply() external view returns (uint256);
}