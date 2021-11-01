// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface IElevenQuickStrat {
    function WITHDRAWAL_FEE() external view returns (uint256);

    function WITHDRAWAL_MAX() external view returns (uint256);
}
