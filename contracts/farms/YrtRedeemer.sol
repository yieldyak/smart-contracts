// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../lib/Ownable.sol";
import "../lib/SafeMath.sol";
import "../lib/SafeERC20.sol";

interface IStrategy {
    function DEPOSITS_ENABLED() external view returns (bool);
}

/**
 * @title YrtRedeemer
 * @author Yield Yak
 * @notice YrtRedeemer is a contract that exchanges the deposit tokens (ERC20) for a redemption token.
 * YrtRedeemer attempts to collect the entire supply of deposit tokens in exchange for redemption tokens at a calculated
 * exchange rate. YrtRedeemer allows anyone to fund redemption tokens exactly ONCE for each deposit token.
 * @dev Important: this contract assumes minting is disabled for each deposit token. If more deposit tokens are minted,
 * the contract may run out of redemption tokens too soon.
 */
contract YrtRedeemer is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /// @notice Redemption token
    IERC20 public immutable redemptionToken;

    /// @notice Total redemption tokens available to redeem for each deposit token
    mapping(IERC20 => uint256) public redemptionBalances;

    /// @notice Outstanding supply for each deposit token
    mapping(IERC20 => uint256) public outstandingSupply;

    /// @notice Funded 
    IERC20[] public eligibleDepositTokens;

    struct Claim {
        IERC20 strategy;
        uint256 amount;
        bool approved;
    }

    event Fund(IERC20 indexed token, uint256 redemptionTokens);
    event Redeem(address indexed account, IERC20 indexed token, uint256 amount, uint256 redemptionTokens);
    event Recovered(IERC20 token, uint256 amount);

    constructor(
        IERC20 _redemptionToken
    ) {
        require(address(_redemptionToken) != address(0), "YrtRedeemer::redemptionToken can't be address(0)");
        redemptionToken = _redemptionToken;
    }

    /**
     * @notice Helper function to get all claims for `claimer`
     * @param claimer address of claimer
     * @return array of Claims
     */
    function getClaims(address claimer) public view returns (Claim[] memory) {
        Claim[] memory claims = new Claim[](eligibleDepositTokens.length);
        for (uint256 i = 0; i < eligibleDepositTokens.length; i++) {
            uint256 balance = eligibleDepositTokens[i].balanceOf(claimer);
            bool approved = eligibleDepositTokens[i].allowance(claimer, address(this)) >= balance;
            claims[i] = Claim(eligibleDepositTokens[i], balance, approved);
        }
        
        return claims;
    }

    /**
     * @notice Enable redemptions for specific depositToken and fund redemption token
     * @dev Restricted to `onlyOwner` to avoid griefing
     * @param depositToken deposit token address
     * @param amount redemption token amount
     */
    function fund(IERC20 depositToken, uint256 amount) external onlyOwner {
        require(redemptionBalances[depositToken] == 0, "YrtRedeemer::depositToken already funded");
        require(outstandingSupply[depositToken] == 0, "YrtRedeemer::outstandingSupply already set");
        require(!IStrategy(address(depositToken)).DEPOSITS_ENABLED(), "YrtRedeemer::deposits enabled");

        uint256 totalSupply = depositToken.totalSupply();
        require(totalSupply > 0, "YrtRedeemer::no depositTokens to collect");

        outstandingSupply[depositToken] = totalSupply;
        redemptionBalances[depositToken] = amount;
        eligibleDepositTokens.push(depositToken);

        redemptionToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Fund(depositToken, amount);
    }

    /**
     * @notice Redeem all possible claims
     */
    function redeemAll() external {
        Claim[] memory claims = getClaims(msg.sender);
        for (uint i = 0; i < claims.length; i++) {
            if (claims[i].amount > 0 && claims[i].approved) {
                redeem(claims[i].strategy, claims[i].amount);
            }
        }
    }

    /**
     * @notice Redeem deposit token balance for redemption tokens
     * @param depositToken deposit token address
     */
    function redeem(IERC20 depositToken, uint256 amount) public {
        depositToken.safeTransferFrom(msg.sender, address(this), amount);

        uint256 redemptionTokens = getRedemptionTokensForShares(depositToken, amount);
        require(redemptionTokens > 0, "redeem::Nothing to redeem");
        redemptionToken.safeTransfer(msg.sender, redemptionTokens);
        emit Redeem(msg.sender, depositToken, amount, redemptionTokens);
    }

    /**
     * @notice Calculates exchange rate for depositToken amount
     * @param depositToken deposit token address
     * @param amount deposit token amount
     * @return redemptionAmount redemption token amount
     */
    function getRedemptionTokensForShares(IERC20 depositToken, uint256 amount) public view returns (uint256 redemptionAmount) {
        uint256 totalRedemptionBalance = redemptionBalances[depositToken];
        uint256 totalShares = outstandingSupply[depositToken];
        if (totalShares == 0 || totalRedemptionBalance == 0) {
            return 0;
        }
        return amount.mul(totalRedemptionBalance).div(totalShares);
    }

    /**
     * @notice Recover ERC20 from contract
     * @param token token address
     * @param amount amount to recover
     */
    function recoverERC20(IERC20 token, uint256 amount) external onlyOwner {
        require(amount > 0, "recoverERC20::Nothing to recover");
        token.safeTransfer(msg.sender, amount);
        emit Recovered(token, amount);
    }
}
