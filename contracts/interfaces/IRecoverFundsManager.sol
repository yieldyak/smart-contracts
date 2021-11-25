// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface IRecoverFundsManager {
    function recoverFundsERC20(
        address owner,
        address tokenToRecover,
        address yakStrategy
    ) external returns (address);

    function recoverFundsAVAX(address owner) external payable returns (address);
}
