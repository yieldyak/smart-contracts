// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface IYakStrategy {
    function balanceOf(address account) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function depositToken() external view returns (address);

    function depositFor(address account, uint256 amount) external;

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}
