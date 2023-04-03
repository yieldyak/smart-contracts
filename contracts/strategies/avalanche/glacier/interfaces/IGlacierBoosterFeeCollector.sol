// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IGlacierBoosterFeeCollector {
    function calculateBoostFee(address _strategy, uint256 _amount) external view returns (uint256, address);
}
