// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IPlatypusAsset {
    function cash() external view returns (uint256);

    function liability() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function pool() external view returns (address);

    function underlyingToken() external view returns (address);
}
