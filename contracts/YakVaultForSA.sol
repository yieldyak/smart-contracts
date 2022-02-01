// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;
pragma experimental ABIEncoderV2;

import "./YakERC20.sol";
import "./lib/SafeMath.sol";
import "./lib/Ownable.sol";
import "./lib/EnumerableSet.sol";
import "./lib/SafeERC20.sol";
import "./interfaces/IERC20.sol";
import "./YakRegistry.sol";
import "./YakStrategy.sol";

/**
 * @notice YakVault is a managed vault for `deposit tokens` that accepts deposits in the form of `deposit tokens` OR `strategy tokens`.
 */
contract YakVaultForSA is YakERC20, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 internal constant BIPS_DIVISOR = 10000;

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
        require(amount > 0, "YakVault::deposit, amount too low");
        require(checkStrategies() == true, "YakVault::deposit paused");
        _mint(account, getSharesForDepositTokens(amount));
        IERC20(depositToken).safeTransferFrom(msg.sender, address(this), amount);
        if (activeStrategy != address(0)) {
            depositToken.safeApprove(activeStrategy, amount);
            YakStrategy(activeStrategy).deposit(amount);
            depositToken.safeApprove(activeStrategy, 0);
        }
        emit Deposit(account, address(depositToken), amount);
    }

    /**
     * @notice Withdraw from the vault
     * @param amount receipt tokens
     */
    function withdraw(uint256 amount) external {
        require(checkStrategies() == true, "YakVault::withdraw paused");
        uint256 depositTokenAmount = getDepositTokensForShares(amount);
        require(depositTokenAmount > 0, "YakVault::withdraw, amount too low");
        uint256 liquidDeposits = depositToken.balanceOf(address(this));
        uint256 remainingDebt = depositTokenAmount.sub(liquidDeposits);
        if (remainingDebt > 0) {
            for (uint256 i = 0; i < supportedStrategies.length(); i++) {
                address strategy = supportedStrategies.at(i);
                uint256 deployedBalance = getDeployedBalance(strategy);
                if (deployedBalance > remainingDebt) {
                    _withdrawFromStrategy(strategy, remainingDebt);
                    break;
                } else if (deployedBalance > 0) {
                    _withdrawPercentageFromStrategy(strategy, 10000);
                    remainingDebt = remainingDebt.sub(deployedBalance);
                    if (remainingDebt <= 1) {
                        break;
                    }
                }
            }
            uint256 balance = depositToken.balanceOf(address(this));
            if (balance < depositTokenAmount) {
                depositTokenAmount = balance;
            }
        }
        depositToken.safeTransfer(msg.sender, depositTokenAmount);
        _burn(msg.sender, amount);
        emit Withdraw(msg.sender, depositTokenAmount);
    }

    function checkStrategies() internal view returns (bool) {
        for (uint256 i = 0; i < supportedStrategies.length(); i++) {
            if (!yakRegistry.isEnabledStrategy(supportedStrategies.at(i))) {
                return false;
            }
        }
        return true;
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
        require(
            yakRegistry.pausedStrategies(strategy) == false,
            "YakVault::removeStrategy, cannot remove paused strategy"
        );
        require(strategy != activeStrategy, "YakVault::removeStrategy, cannot remove activeStrategy");
        require(supportedStrategies.contains(strategy) == true, "YakVault::removeStrategy, not supported");
        require(
            getDeployedBalance(strategy) == 0 || yakRegistry.disabledStrategies(strategy) == true,
            "YakVault::cannot remove enabled strategy with funds"
        );
        depositToken.safeApprove(strategy, 0);
        supportedStrategies.remove(strategy);
        emit RemoveStrategy(strategy);
    }

    /**
     * @notice Owner method for removing funds from strategy (to rebalance, typically)
     * @param strategy address
     * @param amount deposit tokens
     */
    function withdrawFromStrategy(address strategy, uint256 amount) public onlyOwner {
        _withdrawFromStrategy(strategy, amount);
    }

    function _withdrawFromStrategy(address strategy, uint256 amount) private {
        uint256 balanceBefore = depositToken.balanceOf(address(this));
        uint256 withdrawalStrategyShares = 0;
        withdrawalStrategyShares = YakStrategy(strategy).getSharesForDepositTokens(amount);
        YakStrategy(strategy).withdraw(withdrawalStrategyShares);
        uint256 balanceAfter = depositToken.balanceOf(address(this));
        require(balanceAfter > balanceBefore, "YakVault::_withdrawDepositTokensFromStrategy withdrawal failed");
    }

    /**
     * @notice Owner method for removing funds from strategy (to rebalance, typically)
     * @param strategy address
     * @param withdrawPercentageBips percentage to withdraw from strategy, 10000 = 100%
     */
    function withdrawPercentageFromStrategy(address strategy, uint256 withdrawPercentageBips) public onlyOwner {
        _withdrawPercentageFromStrategy(strategy, withdrawPercentageBips);
    }

    function _withdrawPercentageFromStrategy(address strategy, uint256 withdrawPercentageBips) private {
        require(
            withdrawPercentageBips > 0 && withdrawPercentageBips <= BIPS_DIVISOR,
            "YakVault::_withdrawPercentageFromStrategy invalid percentage"
        );
        uint256 balanceBefore = depositToken.balanceOf(address(this));
        uint256 withdrawalStrategyShares = 0;
        uint256 shareBalance = YakStrategy(strategy).balanceOf(address(this));
        withdrawalStrategyShares = shareBalance.mul(withdrawPercentageBips).div(BIPS_DIVISOR);
        YakStrategy(strategy).withdraw(withdrawalStrategyShares);
        uint256 balanceAfter = depositToken.balanceOf(address(this));
        require(balanceAfter > balanceBefore, "YakVault::_withdrawPercentageFromStrategy withdrawal failed");
    }

    /**
     * @notice Owner method for deposit funds into strategy
     * @param strategy address
     * @param amount deposit tokens
     */
    function depositToStrategy(address strategy, uint256 amount) public onlyOwner {
        require(supportedStrategies.contains(strategy), "YakVault::depositToStrategy strategy");
        uint256 depositTokenBalance = depositToken.balanceOf(address(this));
        require(depositTokenBalance >= amount, "YakVault::depositToStrategy amount");
        depositToken.safeApprove(strategy, amount);
        YakStrategy(strategy).deposit(amount);
        depositToken.safeApprove(strategy, 0);
    }

    /**
     * @notice Owner method for deposit funds into strategy
     * @param strategy address
     * @param depositPercentageBips percentage to deposit into strategy, 10000 = 100%
     */
    function depositPercentageToStrategy(address strategy, uint256 depositPercentageBips) public onlyOwner {
        require(
            depositPercentageBips > 0 && depositPercentageBips <= BIPS_DIVISOR,
            "YakVault::depositPercentageToStrategy invalid percentage"
        );
        require(supportedStrategies.contains(strategy), "YakVault::depositPercentageToStrategy strategy");
        uint256 depositTokenBalance = depositToken.balanceOf(address(this));
        require(depositTokenBalance >= 0, "YakVault::depositPercentageToStrategy balance zero");
        uint256 amount = depositTokenBalance.mul(depositPercentageBips).div(BIPS_DIVISOR);
        depositToken.safeApprove(strategy, amount);
        YakStrategy(strategy).deposit(amount);
        depositToken.safeApprove(strategy, 0);
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
