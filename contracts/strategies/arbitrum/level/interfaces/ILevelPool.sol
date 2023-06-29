// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface ILevelPool {
    function addLiquidity(address tranche, address assetToken, uint256 assetAmount, uint256 minLpAmount, address to)
        external;
}
