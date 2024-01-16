// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../BaseLendingStrategy.sol";
import "./interfaces/IIncentivesController.sol";
import "./interfaces/IMultiFeeDistribution.sol";
import "./interfaces/ILendingPoolAaveV3.sol";

contract LendleStrategy is BaseLendingStrategy {
    using SafeERC20 for IERC20;

    struct LendleStrategySettings {
        address incentivesController;
        address lendingPool;
        address avToken;
        address avDebtToken;
        uint256 safetyFactor;
        uint256 minMinting;
    }

    address constant LEND = 0x25356aeca4210eF7553140edb9b8026089E49396;

    uint256 public safetyFactor;
    uint256 public minMinting;

    IIncentivesController public immutable incentivesController;
    IMultiFeeDistribution public immutable multiFeeDistribution;
    ILendingPoolAaveV3 public immutable lendingPool;
    address public immutable avToken;
    address public immutable avDebtToken;

    constructor(
        LendleStrategySettings memory _lendleStrategySettings,
        BaseLendingStrategySettings memory _baseLendingStrategySettings,
        BaseStrategySettings memory _baseStrategySettings,
        StrategySettings memory _strategySettings
    ) BaseLendingStrategy(_baseLendingStrategySettings, _baseStrategySettings, _strategySettings) {
        incentivesController = IIncentivesController(_lendleStrategySettings.incentivesController);
        multiFeeDistribution = IMultiFeeDistribution(incentivesController.rewardMinter());
        lendingPool = ILendingPoolAaveV3(_lendleStrategySettings.lendingPool);
        _updateLeverage(
            _baseLendingStrategySettings.leverageLevel,
            _baseLendingStrategySettings.leverageBips,
            _lendleStrategySettings.safetyFactor,
            _lendleStrategySettings.minMinting
        );
        avToken = _lendleStrategySettings.avToken;
        avDebtToken = _lendleStrategySettings.avDebtToken;
    }

    function updateLeverage(uint256 _leverageLevel, uint256 _leverageBips, uint256 _safetyFactor, uint256 _minMinting)
        external
        onlyDev
    {
        _updateLeverage(_leverageLevel, _safetyFactor, _minMinting, _leverageBips);
        (uint256 balance, uint256 borrowed,) = _getAccountData();
        _unrollDebt(balance - borrowed);
        _rollupDebt();
    }

    function _updateLeverage(uint256 _leverageLevel, uint256 _leverageBips, uint256 _safetyFactor, uint256 _minMinting)
        internal
    {
        leverageLevel = _leverageLevel;
        leverageBips = _leverageBips;
        safetyFactor = _safetyFactor;
        minMinting = _minMinting;
    }

    function getActualLeverage() public view returns (uint256) {
        (uint256 balance, uint256 borrowed,) = _getAccountData();
        return (balance * 1e18) / (balance - borrowed);
    }

    function _supplyAssets(uint256 _amount) internal override {
        depositToken.approve(address(lendingPool), _amount);
        lendingPool.deposit(address(depositToken), _amount, address(this), 0);
    }

    function _withdrawAssets(uint256 _amount) internal override returns (uint256 withdrawAmount) {
        (uint256 balance,,) = _getAccountData();
        _amount = _amount > balance ? type(uint256).max : _amount;
        withdrawAmount = lendingPool.withdraw(address(depositToken), _amount, address(this));
    }

    function _rollupDebt() internal override {
        (uint256 balance, uint256 borrowed, uint256 borrowable) = _getAccountData();
        uint256 lendTarget = ((balance - borrowed) * (leverageLevel - safetyFactor)) / (leverageBips);
        depositToken.approve(address(lendingPool), lendTarget);
        while (balance < lendTarget) {
            if (balance + borrowable > lendTarget) {
                borrowable = lendTarget - balance;
            }

            if (borrowable < minMinting) {
                break;
            }

            lendingPool.borrow(
                address(depositToken),
                borrowable,
                2, // variable interest model
                0,
                address(this)
            );

            lendingPool.deposit(address(depositToken), borrowable, address(this), 0);
            (balance, borrowed, borrowable) = _getAccountData();
        }
        depositToken.approve(address(lendingPool), 0);
    }

    function _getRedeemable(uint256 balance, uint256 borrowed, uint256 threshold) internal pure returns (uint256) {
        return (((balance - borrowed) * 1e18) - (((((borrowed * 13) / 10) * 1e18) / threshold) / 100000)) / 1e18;
    }

    function _unrollDebt(uint256 _amountNeeded) internal override {
        (uint256 balance, uint256 borrowed, uint256 borrowable) = _getAccountData();
        uint256 targetBorrow = (
            (((balance - borrowed) - _amountNeeded) * (leverageLevel - safetyFactor)) / leverageBips
        ) - (balance - borrowed - _amountNeeded);
        uint256 toRepay = borrowed - targetBorrow;
        while (toRepay > 0) {
            uint256 unrollAmount = borrowable;
            if (unrollAmount > borrowed) {
                unrollAmount = borrowed;
            }
            lendingPool.withdraw(address(depositToken), unrollAmount, address(this));
            depositToken.approve(address(lendingPool), unrollAmount);
            lendingPool.repay(address(depositToken), unrollAmount, 2, address(this));
            (balance, borrowed, borrowable) = _getAccountData();
            if (targetBorrow >= borrowed) {
                break;
            }
            toRepay = borrowed - targetBorrow;
        }
    }

    /// @notice Internal method to get account state
    /// @dev Values provided in 1e18 (WAD) instead of 1e27 (RAY)
    function _getAccountData() internal view returns (uint256 balance, uint256 borrowed, uint256 borrowable) {
        balance = IERC20(avToken).balanceOf(address(this));
        borrowed = IERC20(avDebtToken).balanceOf(address(this));
        if ((balance * (leverageLevel - leverageBips)) / leverageLevel > borrowed) {
            borrowable = ((balance * (leverageLevel - leverageBips)) / leverageLevel) - borrowed;
        }
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        address[] memory assets = new address[](2);
        assets[0] = avToken;
        assets[1] = avDebtToken;
        uint256[] memory amounts = incentivesController.claimableReward(address(this), assets);
        Reward[] memory pendingRewards = new Reward[](1);
        pendingRewards[0] = Reward({reward: LEND, amount: (amounts[0] + amounts[1]) / 2});
        return pendingRewards;
    }

    function _getRewards() internal override {
        address[] memory assets = new address[](2);
        assets[0] = avToken;
        assets[1] = avDebtToken;
        incentivesController.claim(address(this), assets);
        multiFeeDistribution.exit(true);
    }

    function totalDeposits() public view override returns (uint256) {
        (uint256 balance, uint256 borrowed,) = _getAccountData();
        return balance - borrowed;
    }

    function _emergencyWithdraw() internal override {
        (uint256 balance, uint256 borrowed,) = _getAccountData();
        _unrollDebt(balance - borrowed);
        lendingPool.withdraw(address(depositToken), type(uint256).max, address(this));
    }
}
