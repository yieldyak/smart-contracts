// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "./YakERC20.sol";
import "./lib/SafeMath.sol";
import "./lib/Ownable.sol";
import "./interfaces/IERC20.sol";
import "./YakStrategy.sol";

/**
 * @notice YakVault is a managed vault for `deposit tokens` that accepts deposits in the form of `deposit tokens` OR `strategy tokens`.
 * @dev DRAFT
 */
contract YakVault is YakERC20, Ownable {
    using SafeMath for uint;

    /// @notice Vault version number
    string public constant version = "0.0.1";

    /// @notice Deposit token that the vault manages
    IERC20 public depositToken;

    /// @notice Total deposits in terms of depositToken
    uint public totalDeposits;

    /// @notice Active strategy where deposits are sent by default
    address public activeStrategy;

    /// @notice Supported deposit tokens (Yak Receipt Tokens, usually)
    mapping(address => bool) public supportedDepositTokens;

    /// @notice Supported strategies
    address[] public supportedStrategies;

    event Deposit(address indexed account, address indexed token, uint amount);
    event Withdraw(address indexed account, uint amount);
    event AddStrategy(address indexed strategy);
    event RemoveStrategy(address indexed strategy);
    event SetActiveStrategy(address indexed strategy);
    event Sync(uint newTotalDeposits, uint newTotalSupply);

    constructor (
        string memory _name,
        address _depositToken
    ) {
        name = _name;
        depositToken = IERC20(_depositToken);

        supportedDepositTokens[_depositToken] = true;
    }

    /**
     * @notice Deposit to currently active strategy
     * @dev Vaults may allow multiple types of tokens to be deposited
     * @dev By default, Vaults send new deposits to the active strategy
     * @param token address
     * @param amount amount
     */
    function deposit(address token, uint amount) external {
        _deposit(msg.sender, token, amount);
    }

    function depositWithPermit(address token, uint amount, uint deadline, uint8 v, bytes32 r, bytes32 s) external {
        IERC20(token).permit(msg.sender, address(this), amount, deadline, v, r, s);
        _deposit(msg.sender, token, amount);
    }

    function depositFor(address account, address token, uint amount) external {
        _deposit(account, token, amount);
    }

    function _deposit(address account, address token, uint amount) private {
        require(supportedDepositTokens[token], "YakVault::deposit, token not supported");
        require(activeStrategy != address(0), "YakVault::no active strategy");
        uint balanceBefore = IERC20(token).balanceOf(address(this));
        require(IERC20(token).transferFrom(msg.sender, address(this), amount), "YakVault::deposit, failed");
        uint balanceAfter = IERC20(token).balanceOf(address(this));
        uint confirmedAmount = balanceAfter.sub(balanceBefore);
        require(confirmedAmount > 0, "YakVault::deposit, amount too low");
        if (token == address(depositToken)) {
            YakStrategy(activeStrategy).deposit(confirmedAmount);
        }
        // todo - conversion for other token deposits
        _mint(account, getSharesForDepositTokens(amount));
        totalDeposits = totalDeposits.add(amount);
        emit Deposit(account, token, amount);
        emit Sync(totalDeposits, totalSupply);
    }

    /**
     * @notice Withdraw from strategies
     * @param amount receipt tokens
     */
    function withdraw(uint amount) external {
        uint depositTokenAmount = getDepositTokensForShares(amount);
        require(depositTokenAmount > 0, "YakVault::withdraw, amount too low");
        uint liquidDeposits = depositToken.balanceOf(address(this));
        uint remainingDebt = depositTokenAmount.sub(liquidDeposits);
        if (remainingDebt > 0) {
            for (uint i = 0; i < supportedStrategies.length; i++) {
                uint deployedBalance = getDeployedBalance(supportedStrategies[i]);
                if (deployedBalance >= remainingDebt) {
                    withdrawFromStrategy(supportedStrategies[i], remainingDebt);
                    break;
                }
                else {
                    withdrawFromStrategy(supportedStrategies[i], deployedBalance);
                    remainingDebt = remainingDebt.sub(deployedBalance);
                }
            }
        }
        _safeTransfer(address(depositToken), msg.sender, depositTokenAmount);
        _burn(msg.sender, amount);
        totalDeposits = totalDeposits.sub(depositTokenAmount);
        emit Withdraw(msg.sender, depositTokenAmount);
        emit Sync(totalDeposits, totalSupply);
    }

    function _revokeApproval(address token, address spender) internal {
        require(IERC20(token).approve(spender, 0), "YakVault::revokeApproval");
    }

    /**
     * @notice Safely transfer using an anonymosu ERC20 token
     * @dev Requires token to return true on transfer
     * @param token address
     * @param to recipient address
     * @param value amount
     */
    function _safeTransfer(address token, address to, uint256 value) private {
        require(IERC20(token).transfer(to, value), 'YakVault::TRANSFER_FROM_FAILED');
    }

    /**
     * @notice Set an active strategy
     * @dev Set to address(0) to disable deposits
     * @param strategy address for new strategy
     */
    function setActiveStrategy(address strategy) public onlyOwner {
        require(supportedDepositTokens[strategy], "YakVault::setActiveStrategy, not found");
        require(depositToken.approve(strategy, uint(-1)));
        activeStrategy = strategy;
        emit SetActiveStrategy(strategy);
    }

    /**
     * @notice Add a supported strategy and allow deposits
     * @dev Makes light checks for compatible deposit tokens
     */
    function addStrategy(address strategy) public onlyOwner {
        require(supportedDepositTokens[strategy] == false, "YakVault::addStrategy, already supported");
        require(depositToken == YakStrategy(strategy).depositToken(), "YakVault::addStrategy, not compatible");
        supportedDepositTokens[strategy] = true;
        supportedStrategies.push(strategy);
        emit AddStrategy(strategy);
    }

    /**
     * @notice Remove a supported strategy and revoke approval
     */
    function removeStrategy(address strategy) public onlyOwner {
        require(strategy != activeStrategy, "YakVault::removeStrategy, cannot remove activeStrategy");
        require(strategy != address(depositToken), "YakVault::removeStrategy, cannot remove deposit token");
        require(supportedDepositTokens[strategy] == true, "YakVault::removeStrategy, not supported");
        _revokeApproval(address(depositToken), strategy);
        supportedDepositTokens[strategy] = false;
        // todo: update array
        emit RemoveStrategy(strategy);
    }

    function withdrawFromStrategy(address strategy, uint amount) public onlyOwner {
        uint balanceBefore = depositToken.balanceOf(address(this));
        uint strategyShares = YakStrategy(strategy).getSharesForDepositTokens(amount);
        YakStrategy(strategy).withdraw(strategyShares);
        uint balanceAfter = depositToken.balanceOf(address(this));
        require(balanceAfter > balanceBefore, "YakVault::withdrawFromStrategy");
    }

    function getDeployedBalance(address strategy) public view returns (uint) {
        // todo fallback for old version to totalDeposits
        uint deployedInStrategy = YakStrategy(strategy).estimateDeployedBalance();
        uint vaultShares = YakStrategy(strategy).balanceOf(address(this));
        return YakStrategy(strategy).getSharesForDepositTokens(vaultShares);
    }

    /**
     * @notice Count deposit tokens deployed across supported strategies
     * @dev Does not include deprecated strategies
     */
    function estimateDeployedBalances() public view returns (uint) {
        uint deployedFunds = 0;
        for (uint i = 0; i < supportedStrategies.length; i++) {
            deployedFunds = deployedFunds.add(getDeployedBalance(supportedStrategies[i]));
        }
        return deployedFunds;
    }

    /**
     * @notice Calculate deposit tokens for a given amount of receipt tokens
     * @param amount receipt tokens
     * @return deposit tokens
     */
    function getDepositTokensForShares(uint amount) public view returns (uint) {
        if (totalSupply.mul(totalDeposits) == 0) {
            return 0;
        }
        return amount.mul(totalDeposits).div(totalSupply);
    }

    /**
     * @notice Calculate receipt tokens for a given amount of deposit tokens
     * @dev If contract is empty, use 1:1 ratio
     * @dev Could return zero shares for very low amounts of deposit tokens
     * @param amount deposit tokens
     * @return receipt tokens
     */
    function getSharesForDepositTokens(uint amount) public view returns (uint) {
        if (totalSupply.mul(totalDeposits) == 0) {
            return amount;
        }
        return amount.mul(totalSupply).div(totalDeposits);
    }
}