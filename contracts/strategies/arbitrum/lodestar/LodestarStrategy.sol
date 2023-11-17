// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../BaseLendingStrategy.sol";
import "./interfaces/IUnitroller.sol";
import "./interfaces/IERC20Delegator.sol";
import "./lib/LodestarLibrary.sol";

contract LodestarStrategy is BaseLendingStrategy {
    using SafeERC20 for IERC20;

    address immutable LODE;

    struct LodestarStrategySettings {
        address unitroller;
        address tokenDelegator;
        uint256 redeemLimitSafetyMargin;
        uint256 minMinting;
    }

    IUnitroller public immutable unitroller;
    IERC20Delegator public immutable tokenDelegator;

    uint256 public redeemLimitSafetyMargin;
    uint256 public minMinting;

    constructor(
        LodestarStrategySettings memory _lodestarStrategySettings,
        BaseLendingStrategySettings memory _baseLendingStrategySettings,
        BaseStrategySettings memory _baseStrategySettings,
        StrategySettings memory _strategySettings
    ) BaseLendingStrategy(_baseLendingStrategySettings, _baseStrategySettings, _strategySettings) {
        unitroller = IUnitroller(_lodestarStrategySettings.unitroller);
        tokenDelegator = IERC20Delegator(_lodestarStrategySettings.tokenDelegator);
        address[] memory tokens = new address[](1);
        tokens[0] = address(tokenDelegator);
        unitroller.enterMarkets(tokens);
        LODE = unitroller.getCompAddress();
        minMinting = _lodestarStrategySettings.minMinting;
        _updateLeverage(
            _baseLendingStrategySettings.leverageLevel,
            _baseLendingStrategySettings.leverageBips,
            _lodestarStrategySettings.redeemLimitSafetyMargin
        );
    }

    function updateLeverage(uint256 _leverageLevel, uint256 _leverageBips, uint256 _redeemLimitSafetyMargin)
        external
        onlyDev
    {
        _updateLeverage(_leverageLevel, _leverageBips, _redeemLimitSafetyMargin);
        uint256 borrowed = tokenDelegator.borrowBalanceCurrent(address(this));
        uint256 balance = tokenDelegator.balanceOfUnderlying(address(this));
        _unrollDebt(balance - borrowed);
        if (balance - borrowed > 0) {
            _rollupDebt();
        }
    }

    function _updateLeverage(uint256 _leverageLevel, uint256 _leverageBips, uint256 _redeemLimitSafetyMargin)
        internal
    {
        leverageLevel = _leverageLevel;
        leverageBips = _leverageBips;
        redeemLimitSafetyMargin = _redeemLimitSafetyMargin;
    }

    function getActualLeverage() public view returns (uint256) {
        (, uint256 internalBalance, uint256 borrow, uint256 exchangeRate) =
            tokenDelegator.getAccountSnapshot(address(this));
        uint256 balance = (internalBalance * exchangeRate) / 1e18;
        return (balance * 1e18) / (balance - borrow);
    }

    function _supplyAssets(uint256 _amount) internal override {
        depositToken.approve(address(tokenDelegator), _amount);
        tokenDelegator.mint(_amount);
    }

    function _withdrawAssets(uint256 _amount) internal override returns (uint256 withdrawAmount) {
        tokenDelegator.redeemUnderlying(_amount);
        return _amount;
    }

    function _rollupDebt() internal override {
        uint256 borrowed = tokenDelegator.borrowBalanceCurrent(address(this));
        uint256 supplied = tokenDelegator.balanceOfUnderlying(address(this));
        (uint256 borrowLimit, uint256 borrowBips) = _getBorrowLimit();
        uint256 lendTarget = ((supplied - borrowed) * leverageLevel) / leverageBips;
        uint256 totalBorrowed = borrowed;
        depositToken.approve(address(tokenDelegator), lendTarget);
        while (supplied < lendTarget) {
            uint256 toBorrowAmount = _getBorrowable(supplied, totalBorrowed, borrowLimit, borrowBips);
            if (supplied + toBorrowAmount > lendTarget) {
                toBorrowAmount = lendTarget - supplied;
            }
            // safeguard needed because we can't mint below a certain threshold
            if (toBorrowAmount < minMinting) {
                break;
            }
            require(tokenDelegator.borrow(toBorrowAmount) == 0, "BenqiLendingStrategy::borrowing failed");
            require(tokenDelegator.mint(toBorrowAmount) == 0, "BenqiLendingStrategy::lending failed");
            supplied = tokenDelegator.balanceOfUnderlying(address(this));
            totalBorrowed = totalBorrowed + toBorrowAmount;
        }
        depositToken.approve(address(tokenDelegator), 0);
    }

    function _unrollDebt(uint256 _amountNeeded) internal override {
        uint256 borrowed = tokenDelegator.borrowBalanceCurrent(address(this));
        uint256 balance = tokenDelegator.balanceOfUnderlying(address(this));
        uint256 targetBorrow = (((balance - borrowed - _amountNeeded) * leverageLevel) / leverageBips)
            - (balance - borrowed - _amountNeeded);

        uint256 toRepay = borrowed - targetBorrow;
        (uint256 borrowLimit, uint256 borrowBips) = _getBorrowLimit();
        depositToken.approve(address(tokenDelegator), borrowed);
        while (toRepay > 0) {
            uint256 unrollAmount = _getRedeemable(balance, borrowed, borrowLimit, borrowBips);
            if (unrollAmount > toRepay) {
                unrollAmount = toRepay;
            }
            require(tokenDelegator.redeemUnderlying(unrollAmount) == 0, "BenqiLendingStrategy::failed to redeem");
            require(tokenDelegator.repayBorrow(unrollAmount) == 0, "BenqiLendingStrategy::failed to repay borrow");
            balance = tokenDelegator.balanceOfUnderlying(address(this));
            borrowed = tokenDelegator.borrowBalanceCurrent(address(this));
            if (targetBorrow >= borrowed) {
                break;
            }
            toRepay = borrowed - targetBorrow;
        }
    }

    function _getRedeemable(uint256 balance, uint256 borrowed, uint256 borrowLimit, uint256 bips)
        internal
        view
        returns (uint256)
    {
        return ((balance - ((borrowed * bips) / borrowLimit)) * redeemLimitSafetyMargin) / leverageBips;
    }

    function _getBorrowable(uint256 balance, uint256 borrowed, uint256 borrowLimit, uint256 bips)
        internal
        pure
        returns (uint256)
    {
        return ((balance * borrowLimit) / bips) - borrowed;
    }

    function _getBorrowLimit() internal view returns (uint256, uint256) {
        (, uint256 borrowLimit) = unitroller.markets(address(tokenDelegator));
        return (borrowLimit, 1e18);
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        Reward[] memory pendingRewards = new Reward[](1);
        pendingRewards[0] =
            Reward({reward: LODE, amount: LodestarLibrary.calculateReward(unitroller, tokenDelegator, address(this))});
        return pendingRewards;
    }

    function _getRewards() internal override {
        address[] memory ctokens = new address[](1);
        ctokens[0] = address(tokenDelegator);
        unitroller.claimComp(address(this), ctokens);
    }

    function totalDeposits() public view override returns (uint256) {
        (, uint256 internalBalance, uint256 borrow, uint256 exchangeRate) =
            tokenDelegator.getAccountSnapshot(address(this));
        return (internalBalance * exchangeRate / 1e18) - borrow;
    }

    function _emergencyWithdraw() internal override {
        uint256 borrowed = tokenDelegator.borrowBalanceCurrent(address(this));
        uint256 balance = tokenDelegator.balanceOfUnderlying(address(this));
        _unrollDebt(balance - borrowed);
        tokenDelegator.redeemUnderlying(tokenDelegator.balanceOfUnderlying(address(this)));
    }
}
