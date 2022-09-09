// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IVePTP {
    function deposit(uint256 _amount) external;

    function claim() external;

    function claimable(address _addr) external view;

    function withdraw(uint256 _amount) external;

    function totalSupply() external view returns (uint256);

    function balanceOf(address _account) external view returns (uint256);

    function users(address _user)
        external
        view
        returns (
            uint256 amount,
            uint256 lastRelease,
            uint256 stakedNftId
        );

    function getVotes(address _account) external view returns (uint256);
}
