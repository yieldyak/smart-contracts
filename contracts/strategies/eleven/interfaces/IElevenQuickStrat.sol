// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IElevenQuickStrat {
    function WITHDRAWAL_FEE() external view returns (uint);
    function WITHDRAWAL_MAX() external view returns (uint);
}