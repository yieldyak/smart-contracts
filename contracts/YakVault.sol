// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "./YakERC20.sol";
import "./lib/SafeMath.sol";
import "./lib/Ownable.sol";
import "./lib/EnumerableSet.sol";
import "./lib/SafeERC20.sol";
import "./interfaces/IERC20.sol";
import "./YakRegistry.sol";
import "./YakStrategy.sol";
import "hardhat/console.sol";

/**
 * @notice YakVault is a managed vault for `deposit tokens` that accepts deposits in the form of `deposit tokens` OR `strategy tokens`.
 * @dev DRAFT
 */
contract YakVault is YakERC20, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Vault version number
    string public constant version = "0.0.1";

    /// @notice YakRegistry address
    YakRegistry public yakRegistry;

    /// @notice Deposit token that the vault manages
    IERC20 public depositToken;

    /// @notice Active strategy where deposits are sent by default
    address public activeStrategy;

    EnumerableSet.AddressSet internal supportedStrategies;

    event Deposit(address indexed account, address indexed token, uint256 amount);
    event Withdraw(address indexed account, uint256 amount);
    event AddStrategy(address indexed strategy);
    event RemoveStrategy(address indexed strategy);
    event SetActiveStrategy(address indexed strategy);

    constructor(
        string memory _name,
        address _depositToken,
        address _yakRegistry
    ) {
        name = _name;
        depositToken = IERC20(_depositToken);
        yakRegistry = YakRegistry(_yakRegistry);
    }

    /**
     * @notice Deposit to currently active strategy
     * @dev Vaults may allow multiple types of tokens to be deposited
     * @dev By default, Vaults send new deposits to the active strategy
     * @param amount amount
     */
    function deposit(uint256 amount) external {
        _deposit(msg.sender, amount);
    }

    function depositWithPermit(
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        IERC20(depositToken).permit(msg.sender, address(this), amount, deadline, v, r, s);
        _deposit(msg.sender, amount);
    }

    function depositFor(address account, uint256 amount) external {
        _deposit(account, amount);
    }

    function _deposit(address account, uint256 amount) private {
        uint256 balanceBefore = IERC20(depositToken).balanceOf(address(this));
        require(IERC20(depositToken).transferFrom(msg.sender, address(this), amount), "YakVault::deposit, failed");
        uint256 balanceAfter = IERC20(depositToken).balanceOf(address(this));
        uint256 confirmedAmount = balanceAfter.sub(balanceBefore);
        require(confirmedAmount > 0, "YakVault::deposit, amount too low");
        if (activeStrategy != address(0)) {
            depositToken.safeApprove(activeStrategy, confirmedAmount);
            YakStrategy(activeStrategy).deposit(confirmedAmount);
            depositToken.safeApprove(activeStrategy, 0);
        }
        _mint(account, getSharesForDepositTokens(confirmedAmount));
        emit Deposit(account, address(depositToken), confirmedAmount);
    }

    /**
     * @notice Withdraw from the vault
     * @param amount receipt tokens
     */
    function withdraw(uint256 amount) external {
        uint256 depositTokenAmount = getDepositTokensForShares(amount);
        require(depositTokenAmount > 0, "YakVault::withdraw, amount too low");
        uint256 liquidDeposits = depositToken.balanceOf(address(this));
        uint256 remainingDebt = depositTokenAmount.sub(liquidDeposits);
        if (remainingDebt > 0) {
            for (uint256 i = 0; i < supportedStrategies.length(); i++) {
                address strategy = supportedStrategies.at(i);
                uint256 deployedBalance = getDeployedBalance(strategy);
                if (deployedBalance > remainingDebt) {
                    withdrawFromStrategy(strategy, remainingDebt, false);
                    break;
                } else if (deployedBalance > 0) {
                    withdrawFromStrategy(strategy, deployedBalance, true);
                    remainingDebt = remainingDebt.sub(deployedBalance);
                    if (remainingDebt <= 1) {
                        break;
                    }
                }
            }
        }
        uint256 withdrawAmount = depositToken.balanceOf(address(this)).sub(liquidDeposits);
        depositToken.safeTransfer(msg.sender, withdrawAmount);
        _burn(msg.sender, amount);
        emit Withdraw(msg.sender, depositTokenAmount);
    }

    /**
     * @notice Set an active strategy
     * @dev Set to address(0) to disable automatic deposits to active strategy on vault deposits
     * @param strategy address for new strategy
     */
    function setActiveStrategy(address strategy) public onlyOwner {
        require(supportedStrategies.contains(strategy) == true, "YakVault::setActiveStrategy, not found");
        activeStrategy = strategy;
        emit SetActiveStrategy(strategy);
    }

    /**
     * @notice Add a supported strategy and allow deposits
     * @dev Makes light checks for compatible deposit tokens
     * @param strategy address for new strategy
     */
    function addStrategy(address strategy) public onlyOwner {
        require(yakRegistry.isActiveStrategy(strategy) == true, "YakVault::addStrategy, not registered");
        require(supportedStrategies.contains(strategy) == false, "YakVault::addStrategy, already supported");
        require(depositToken == YakStrategy(strategy).depositToken(), "YakVault::addStrategy, not compatible");
        supportedStrategies.add(strategy);
        emit AddStrategy(strategy);
    }

    /**
     * @notice Remove a supported strategy and revoke approval
     * @param strategy address for new strategy
     */
    function removeStrategy(address strategy) public onlyOwner {
        require(strategy != activeStrategy, "YakVault::removeStrategy, cannot remove activeStrategy");
        require(supportedStrategies.contains(strategy) == true, "YakVault::removeStrategy, not supported");
        depositToken.safeApprove(strategy, 0);
        supportedStrategies.remove(strategy);
        emit RemoveStrategy(strategy);
    }

    /**
     * @notice Owner method for removing funds from strategy (to rebalance, typically)
     * @param strategy address
     * @param amount deposit tokens
     */
    function withdrawFromStrategy(
        address strategy,
        uint256 amount,
        bool withdrawBalance
    ) public onlyOwner {
        uint256 balanceBefore = depositToken.balanceOf(address(this));
        uint256 strategyShares = 0;
        if (withdrawBalance) {
            strategyShares = YakStrategy(strategy).balanceOf(address(this));
        } else {
            strategyShares = YakStrategy(strategy).getSharesForDepositTokens(amount);
        }
        YakStrategy(strategy).withdraw(strategyShares);
        uint256 balanceAfter = depositToken.balanceOf(address(this));
        require(balanceAfter > balanceBefore, "YakVault::withdrawFromStrategy");
    }

    /**
     * @notice Owner method for deposit funds into strategy
     * @param strategy address
     * @param amount deposit tokens
     */
    function depositToStrategy(address strategy, uint256 amount) public onlyOwner {
        uint256 depositTokenBalance = depositToken.balanceOf(address(this));
        require(depositTokenBalance >= amount, "YakVault::depositToStrategy amount");
        require(supportedStrategies.contains(strategy), "YakVault::depositToStrategy strategy");
        depositToken.safeApprove(activeStrategy, amount);
        YakStrategy(strategy).deposit(amount);
        depositToken.safeApprove(activeStrategy, 0);
    }

    /**
     * @notice Count deposit tokens deployed in a strategy
     * @param strategy address
     * @return amount deposit tokens
     */
    function getDeployedBalance(address strategy) public view returns (uint256) {
        uint256 vaultShares = YakStrategy(strategy).balanceOf(address(this));
        return YakStrategy(strategy).getDepositTokensForShares(vaultShares);
    }

    /**
     * @notice Count deposit tokens deployed across supported strategies
     * @dev Does not include deprecated strategies
     * @return amount deposit tokens
     */
    function estimateDeployedBalances() public view returns (uint256) {
        uint256 deployedFunds = 0;
        for (uint256 i = 0; i < supportedStrategies.length(); i++) {
            deployedFunds = deployedFunds.add(getDeployedBalance(supportedStrategies.at(i)));
        }
        return deployedFunds;
    }

    /**
     * @notice Calculate deposit tokens for a given amount of receipt tokens
     * @param amount receipt tokens
     * @return deposit tokens
     */
    function getDepositTokensForShares(uint256 amount) public view returns (uint256) {
        if (totalSupply.mul(totalDeposits()) == 0) {
            return 0;
        }
        return amount.mul(totalDeposits()).div(totalSupply);
    }

    /**
     * @notice Calculate receipt tokens for a given amount of deposit tokens
     * @dev If contract is empty, use 1:1 ratio
     * @dev Could return zero shares for very low amounts of deposit tokens
     * @param amount deposit tokens
     * @return receipt tokens
     */
    function getSharesForDepositTokens(uint256 amount) public view returns (uint256) {
        if (totalSupply.mul(totalDeposits()) == 0) {
            return amount;
        }
        return amount.mul(totalSupply).div(totalDeposits());
    }

    function totalDeposits() public view returns (uint256) {
        uint256 deposits = depositToken.balanceOf(address(this));
        for (uint256 i = 0; i < supportedStrategies.length(); i++) {
            YakStrategy strategy = YakStrategy(supportedStrategies.at(i));
            deposits = deposits.add(strategy.getDepositTokensForShares(strategy.balanceOf(address(this))));
        }
        return deposits;
    }
}
