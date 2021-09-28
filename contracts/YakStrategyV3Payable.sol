// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "./lib/Ownable.sol";
import "./YakStrategyV3.sol";
import "./utilities/RecoverFundsAVAX.sol";

/**
 * @notice YakStrategy should be inherited by new strategies
 */
abstract contract YakStrategyV3Payable is YakStrategyV3 {
    /**
     * @notice Deposit and deploy deposits tokens to the strategy using AVAX
     * @dev Must mint receipt tokens to `msg.sender`
     */
    function deposit() external payable virtual;

    /**
     * @notice Deposit on behalf of another account using AVAX
     * @dev Must mint receipt tokens to `account`
     * @param account address to receive receipt tokens
     */
    function depositFor(address account) external payable virtual;

    /**
     * @notice Recover AVAX from contract
     * @param amount amount
     */
    function recoverAVAX(uint256 amount) external override onlyOwner {
        revert(
            "Can't withdraw AVAX as it is depositToken, use emergency withdraw instead"
        );
    }

    function emergencyRescueFunds(uint256 minReturnAmountAccepted)
        external
        override
        onlyOwner
    {
        rescueDeployedFunds(minReturnAmountAccepted, true);
        uint256 balance = address(this).balance;
        recoverFunds = IRecoverFunds(
            address(
                new RecoverFundsAVAX{value: balance}(
                    owner(),
                    address(this),
                    balance
                )
            )
        );
    }
}
