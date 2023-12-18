// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IVotingEscrow {
    function lockedEnd(address _addr) external view returns (uint256);
    function stakeMux(uint256 _amount, uint256 _lockPeriod) external;
}
