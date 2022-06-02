// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./YakBase.sol";
import "./lib/SafeMath.sol";
import "./lib/Ownable.sol";
import "./lib/EnumerableSet.sol";
import "./lib/SafeERC20.sol";
import "./lib/ReentrancyGuard.sol";
import "./YakRegistry.sol";
import "./YakStrategy.sol";

/**
 * @notice YakVault is a managed vault for `deposit tokens` that accepts deposits in the form of `deposit tokens` OR `strategy tokens`.
 */
contract YakVaultForSA is YakBase, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 internal constant BIPS_DIVISOR = 10000;

    /// @notice Vault version number
    string public constant version = "0.0.1";

    /// @notice YakRegistry address
    YakRegistry public yakRegistry;

    /// @notice Active strategy where deposits are sent by default
    address public activeStrategy;

    uint256 public maxSlippageBips;

    EnumerableSet.AddressSet internal supportedStrategies;

    event AddStrategy(address indexed strategy);
    event RemoveStrategy(address indexed strategy);
    event SetActiveStrategy(address indexed strategy);

    constructor(
        address _yakRegistry,
        uint256 _maxSlippageBips,
        BaseSettings memory _baseSettings
    ) YakBase(_baseSettings) {
        yakRegistry = YakRegistry(_yakRegistry);
        maxSlippageBips = _maxSlippageBips;
    }

    /*//////////////////////////////////////////////////////////////
                                DEPOSIT
    //////////////////////////////////////////////////////////////*/

    function deposit(uint256 _assets, uint256) internal override nonReentrant {
        require(_assets > 0, "YakVault::deposit, amount too low");
        require(checkStrategies(), "YakVault::deposit, deposit temporarily paused");
        if (activeStrategy != address(0)) {
            IERC20(asset).approve(activeStrategy, _assets);
            YakStrategy(activeStrategy).deposit(_assets);
            IERC20(asset).approve(activeStrategy, 0);
        }
    }

    /*//////////////////////////////////////////////////////////////
                               WITHDRAW
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Withdraw from the vault
     */
    function withdraw(uint256 _assets, uint256) internal override nonReentrant returns (uint256) {
        require(checkStrategies(), "YakVault::withdraw, withdraw temporarily paused");
        uint256 liquidDeposits = IERC20(asset).balanceOf(address(this));
        if (liquidDeposits < _assets) {
            uint256 remainingDebt = _assets.sub(liquidDeposits);
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
            uint256 balance = IERC20(asset).balanceOf(address(this));
            if (balance < _assets) {
                _assets = balance;
            }
        }
        return _assets;
    }

    function _withdrawFromStrategy(address strategy, uint256 amount) private {
        uint256 balanceBefore = IERC20(asset).balanceOf(address(this));
        uint256 withdrawalStrategyShares = 0;
        withdrawalStrategyShares = YakStrategy(strategy).getSharesForDepositTokens(amount);
        YakStrategy(strategy).withdraw(withdrawalStrategyShares);
        uint256 balanceAfter = IERC20(asset).balanceOf(address(this));
        require(balanceAfter > balanceBefore, "YakVault::_withdrawDepositTokensFromStrategy, withdrawal failed");
    }

    function _withdrawPercentageFromStrategy(address strategy, uint256 withdrawPercentageBips) private {
        require(
            withdrawPercentageBips > 0 && withdrawPercentageBips <= BIPS_DIVISOR,
            "YakVault::_withdrawPercentageFromStrategy, invalid percentage"
        );
        uint256 balanceBefore = IERC20(asset).balanceOf(address(this));
        uint256 withdrawalStrategyShares = 0;
        uint256 shareBalance = YakStrategy(strategy).balanceOf(address(this));
        withdrawalStrategyShares = shareBalance.mul(withdrawPercentageBips).div(BIPS_DIVISOR);
        YakStrategy(strategy).withdraw(withdrawalStrategyShares);
        uint256 balanceAfter = IERC20(asset).balanceOf(address(this));
        require(balanceAfter > balanceBefore, "YakVault::_withdrawPercentageFromStrategy, withdrawal failed");
    }

    function checkStrategies() internal view returns (bool) {
        for (uint256 i = 0; i < supportedStrategies.length(); i++) {
            if (yakRegistry.isHaltedStrategy(supportedStrategies.at(i))) {
                return false;
            }
        }
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                                ACCOUNTING
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Count deposit tokens deployed in a strategy
     * @param strategy address
     * @return amount deposit tokens
     */
    function getDeployedBalance(address strategy) public view returns (uint256) {
        uint256 vaultShares = YakStrategy(strategy).balanceOf(address(this));
        return YakStrategy(strategy).getDepositTokensForShares(vaultShares);
    }

    function totalAssets() public view override returns (uint256) {
        uint256 deposits = IERC20(asset).balanceOf(address(this));
        for (uint256 i = 0; i < supportedStrategies.length(); i++) {
            YakStrategy strategy = YakStrategy(supportedStrategies.at(i));
            deposits = deposits + strategy.getDepositTokensForShares(strategy.balanceOf(address(this)));
        }
        return deposits;
    }

    function previewWithdraw(uint256 _assets) public view override returns (uint256) {
        uint256 maxSlippage = _calculateMaxSlippage(_assets);
        return convertToShares(_assets + maxSlippage);
    }

    function previewRedeem(uint256 _shares) public view override returns (uint256) {
        uint256 assets = convertToAssets(_shares);
        uint256 maxSlippage = _calculateMaxSlippage(assets);
        return assets - maxSlippage;
    }

    function _calculateMaxSlippage(uint256 amount) internal view virtual returns (uint256) {
        return (amount * maxSlippageBips) / BIPS_DIVISOR;
    }

    /*//////////////////////////////////////////////////////////////
                                  ADMIN
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Owner method for deposit funds into strategy
     * @param strategy address
     * @param amount deposit tokens
     */
    function depositToStrategy(address strategy, uint256 amount) public onlyOwner {
        require(supportedStrategies.contains(strategy), "YakVault::depositToStrategy, strategy not registered");
        uint256 depositTokenBalance = IERC20(asset).balanceOf(address(this));
        require(depositTokenBalance >= amount, "YakVault::depositToStrategy, amount exceeds balance");
        IERC20(asset).approve(strategy, amount);
        YakStrategy(strategy).deposit(amount);
        IERC20(asset).approve(strategy, 0);
    }

    /**
     * @notice Owner method for deposit funds into strategy
     * @param strategy address
     * @param depositPercentageBips percentage to deposit into strategy, 10000 = 100%
     */
    function depositPercentageToStrategy(address strategy, uint256 depositPercentageBips) public onlyOwner {
        require(
            depositPercentageBips > 0 && depositPercentageBips <= BIPS_DIVISOR,
            "YakVault::depositPercentageToStrategy, invalid percentage"
        );
        require(
            supportedStrategies.contains(strategy),
            "YakVault::depositPercentageToStrategy, strategy not registered"
        );
        uint256 depositTokenBalance = IERC20(asset).balanceOf(address(this));
        require(depositTokenBalance >= 0, "YakVault::depositPercentageToStrategy, balance zero");
        uint256 amount = depositTokenBalance.mul(depositPercentageBips).div(BIPS_DIVISOR);
        IERC20(asset).approve(strategy, amount);
        YakStrategy(strategy).deposit(amount);
        IERC20(asset).approve(strategy, 0);
    }

    /**
     * @notice Owner method for removing funds from strategy (to rebalance, typically)
     * @param strategy address
     * @param amount deposit tokens
     */
    function withdrawFromStrategy(address strategy, uint256 amount) public onlyOwner {
        _withdrawFromStrategy(strategy, amount);
    }

    /**
     * @notice Owner method for removing funds from strategy (to rebalance, typically)
     * @param strategy address
     * @param withdrawPercentageBips percentage to withdraw from strategy, 10000 = 100%
     */
    function withdrawPercentageFromStrategy(address strategy, uint256 withdrawPercentageBips) public onlyOwner {
        _withdrawPercentageFromStrategy(strategy, withdrawPercentageBips);
    }

    /**
     * @notice Set an active strategy
     * @dev Set to address(0) to disable automatic deposits to active strategy on vault deposits
     * @param strategy address for new strategy
     */
    function setActiveStrategy(address strategy) public onlyOwner {
        require(
            strategy == address(0) || supportedStrategies.contains(strategy),
            "YakVault::setActiveStrategy, not found"
        );
        activeStrategy = strategy;
        emit SetActiveStrategy(strategy);
    }

    /**
     * @notice Add a supported strategy and allow deposits
     * @dev Makes light checks for compatible deposit tokens
     * @param strategy address for new strategy
     */
    function addStrategy(address strategy) public onlyOwner {
        require(yakRegistry.isActiveStrategy(strategy), "YakVault::addStrategy, not registered");
        require(supportedStrategies.contains(strategy) == false, "YakVault::addStrategy, already supported");
        require(asset == address(YakStrategy(strategy).depositToken()), "YakVault::addStrategy, not compatible");
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
        require(supportedStrategies.contains(strategy), "YakVault::removeStrategy, not supported");
        require(
            yakRegistry.disabledStrategies(strategy) || getDeployedBalance(strategy) == 0,
            "YakVault::removeStrategy, cannot remove enabled strategy with funds"
        );
        IERC20(asset).approve(strategy, 0);
        supportedStrategies.remove(strategy);
        emit RemoveStrategy(strategy);
    }

    /**
     * @notice Update max slippage for withdrawal
     * @dev Function name matches interface for FeeCollector
     */
    function updateMaxSwapSlippage(uint256 _slippageBips) public onlyDev {
        maxSlippageBips = _slippageBips;
    }

    /*//////////////////////////////////////////////////////////////
                            LEGACY INTERFACE
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Deprecated; Use "asset"
     */
    function depositToken() public view returns (address) {
        return asset;
    }

    /**
     * @dev Deprecated; Use "deposit(uint256 assets, address receiver)"
     */
    function deposit(uint256 _assets) external {
        deposit(_assets, msg.sender);
    }

    /**
     * @dev Deprecated; Use "withdraw(uint256 assets, address receiver, address owner)"
     */
    function withdraw(uint256 _shares) external {
        redeem(_shares, msg.sender, msg.sender);
    }

    /**
     * @dev Deprecated; Use "totalAssets()"
     */
    function totalDeposits() public view returns (uint256) {
        return totalAssets();
    }

    /**
     * @dev Deprecated; Use "convertToShares()"
     */
    function getSharesForDepositTokens(uint256 _amount) public view returns (uint256) {
        return convertToShares(_amount);
    }

    /**
     * @dev Deprecated; Use "convertToAssets()"
     */
    function getDepositTokensForShares(uint256 _amount) public view returns (uint256) {
        return convertToAssets(_amount);
    }
}
