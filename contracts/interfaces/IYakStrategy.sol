// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

interface IYakStrategy {
    function depositToken() external view returns (address);
    function depositFor(address account, uint amount) external;
}