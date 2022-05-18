// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IVectorJoePoolHelper {
    function balanceOf(address _address) external view returns (uint256);

    function mainStakingJoe() external view returns (address);

    function masterVtx() external view returns (address);

    function stakingToken() external view returns (address);

    function earned(address _token) external view returns (uint256 vtxAmount, uint256 tokenAmount);

    function deposit(uint256 _amount) external;

    function stake(uint256 _amount) external;

    function withdraw(uint256 _amount) external;

    function getReward() external;
}
