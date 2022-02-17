// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "./RecoverFunds.sol";
import "./RecoverFundsAVAX.sol";

contract RecoverFundsManager {
    mapping(address => address) public recoveries;

    receive() external payable {
        revert(); // dont accept AVAX as fallback from anyone
    }

    function recoverFundsERC20(
        address owner,
        address tokenToRecover,
        address yakStrategy
    ) external returns (address) {
        recoveries[msg.sender] = address(
            new RecoverFunds(owner, tokenToRecover, yakStrategy)
        );
        return recoveries[msg.sender];
    }

    function recoverFundsAVAX(address owner) external payable returns (address) {
        recoveries[msg.sender] = address(
            new RecoverFundsAVAX{value: msg.value}(owner, msg.sender)
        );
        return recoveries[msg.sender];
    }
}
