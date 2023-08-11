// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./interfaces/IRateProvider.sol";
import "./interfaces/IGAvax.sol";

/**
 * @title yyAVAX Rate Provider
 * @notice Returns the value of yyAVAX in terms of AVAX
 * @dev Stored rate is read from gAVAX (ERC-1155) using yyAVAX's id.
 */
contract YyAvaxRateProvider is IRateProvider {

    /// @notice Geode's ERC-1155 address
    address private constant gAVAX = 0x6026a85e11BD895c934Af02647E8C7b4Ea2D9808;

    /// @notice Geode's id for yyAVAX
    uint256 private constant _id = 45756385483164763772015628191198800763712771278583181747295544980036831301432;

    /**
     * @notice Returns the value of yyAVAX in terms of AVAX
     */
    function getRate() external view returns (uint256) {
        return IGAvax(gAVAX).pricePerShare(_id);
    }
}