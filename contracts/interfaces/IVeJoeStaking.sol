// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

interface IVeJoeStaking {
    function deposit(uint256 _amount) external;

    function claim() external;

    function getPendingVeJoe(address _user) external view returns (uint256);
}
