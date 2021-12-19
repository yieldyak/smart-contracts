// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

interface ISnowballProxy {
    function withdraw(address _stakingContract, address _snowGlobe, address _token, uint _amount) external returns (uint256);
    function withdrawAll(address _stakingContract, address _snowGlobe, address _token) external;
    function balanceOf(address _stakingContract, address _snowGlobe) external view returns (uint256);
    function deposit(address _stakingContract, address _snowGlobe, address _token) external;
    function checkReward(address _stakingContract) external view returns (uint);
    function claimReward(address _stakingContract) external;
}