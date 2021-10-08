// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface ILiquidityGuage {
    function deposit(uint256 _amount,  address _user) external;
    function withdraw(uint256 _amount) external;
    function balanceOf(address owner) external view returns (uint); 
    function claim_rewards() external returns (uint);
}