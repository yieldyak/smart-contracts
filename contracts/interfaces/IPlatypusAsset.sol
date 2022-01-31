// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

interface IPlatypusAsset {
    function cash() external view returns (uint256);

    function liability() external view returns (uint256);

    function totalSupply() external view returns (uint256);
}
