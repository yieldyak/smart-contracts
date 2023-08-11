// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IBalMinter {
    function minted(address user, address gauge) external view returns (uint256);
    function mint(address gauge) external;
    function isValidGaugeFactory(address gauge) external view returns (bool);
}
