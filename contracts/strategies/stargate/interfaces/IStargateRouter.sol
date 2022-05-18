// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IStargateRouter {
    function addLiquidity(
        uint256 _poolId,
        uint256 _amountLD,
        address _to
    ) external;
}
