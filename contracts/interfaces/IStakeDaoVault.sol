// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

interface IStakeDaoVault {
    function deposit(uint256 _amount) external;

    function totalSupply() external view returns (uint256);

    function balance() external view returns (uint256);

    function withdraw(uint256 amount) external;

    function withdrawAll() external;

    function controller() external view returns (address);
}
