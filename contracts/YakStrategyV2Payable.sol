// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "./lib/SafeMath.sol";
import "./lib/Ownable.sol";
import "./lib/Permissioned.sol";
import "./interfaces/IERC20.sol";
import "./YakERC20.sol";
import "./YakStrategyV2.sol";

/**
 * @notice YakStrategy should be inherited by new strategies
 */
abstract contract YakStrategyV2Payable is YakStrategyV2 {
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
}
