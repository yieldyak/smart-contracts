// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "./RecoverFunds.sol";
import "./RecoverFundsAVAX.sol";

contract RecoverFundsManager {
    receive() external payable {
        revert(); // dont accept AVAX as fallback from anyone
    }

    function recoverFundsERC20(
        address owner,
        address tokenToRecover,
        address yakStrategy,
        uint256 balance
    ) external returns (address) {
        return
            address(
                new RecoverFunds(owner, tokenToRecover, yakStrategy, balance)
            );
    }

    function recoverFundsAVAX(address owner)
        external
        payable
        returns (address)
    {
        return
            address(new RecoverFundsAVAX{value: msg.value}(owner, msg.sender));
    }
}
