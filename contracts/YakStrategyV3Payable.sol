// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "./YakStrategyV3.sol";

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
        revert("not allowed");
    }

    function emergencyRescueFunds(uint256 minReturnAmountAccepted)
        external
        override
        onlyOwner
    {
        rescueDeployedFunds(minReturnAmountAccepted);
        //stops deposits
        if (DEPOSITS_ENABLED == true) {
            updateDepositsEnabled(false);
        }

        recoverFunds = recoverFundsManager.recoverFundsAVAX{
            value: address(this).balance
        }(owner());
    }
}
