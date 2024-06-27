// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../BaseLendingStrategy.sol";
import "./interfaces/IBenqiUnitroller.sol";
import "./interfaces/IBenqiERC20Delegator.sol";
import "./lib/BenqiLibrary.sol";

contract BenqiStrategyV4 is BaseLendingStrategy {
    address private constant QI = 0x8729438EB15e2C8B576fCc6AeCdA6A148776C0F5;

    IBenqiUnitroller public comptroller;
    IBenqiERC20Delegator public tokenDelegator;
    uint256 public minMinting;
    uint256 public redeemLimitSafetyMargin;

    constructor(
        address _comptroller,
        address _tokenDelegator,
        uint256 _minMinting,
        BaseLendingStrategySettings memory _baseLendingStrategySettings,
        BaseStrategySettings memory _baseStrategySettings,
        StrategySettings memory _strategySettings
    ) BaseLendingStrategy(_baseLendingStrategySettings, _baseStrategySettings, _strategySettings) {
        comptroller = IBenqiUnitroller(_comptroller);
        tokenDelegator = IBenqiERC20Delegator(_tokenDelegator);
        minMinting = _minMinting;
        _updateLeverage(
            _baseLendingStrategySettings.leverageLevel,
            _baseLendingStrategySettings.leverageBips,
            (_baseLendingStrategySettings.leverageBips * 990) / 1000 // works as long as leverageBips > 1000
        );
        _enterMarket();
    }

    function _enterMarket() internal {
        address[] memory tokens = new address[](1);
        tokens[0] = address(tokenDelegator);
        comptroller.enterMarkets(tokens);
    }

    function _updateLeverage(uint256 _leverageLevel, uint256 _leverageBips, uint256 _redeemLimitSafetyMargin)
        internal
    {
        leverageLevel = _leverageLevel;
        leverageBips = _leverageBips;
        redeemLimitSafetyMargin = _redeemLimitSafetyMargin;
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

    function getActualLeverage() public view returns (uint256) {
        (, uint256 internalBalance, uint256 borrow, uint256 exchangeRate) =
            tokenDelegator.getAccountSnapshot(address(this));
        uint256 balance = (internalBalance * exchangeRate) / 1e18;
        return (balance * 1e18) / (balance - borrow);
    }

    function beforeDeposit() internal override {
        tokenDelegator.accrueInterest();
    }

    function _supplyAssets(uint256 _amount) internal override {
        IERC20(address(depositToken)).approve(address(tokenDelegator), _amount);
        require(tokenDelegator.mint(_amount) == 0, "BenqiLendingStrategy::Deposit failed");
    }

    function beforeWithdraw() internal override {
        tokenDelegator.accrueInterest();
    }

    function _withdrawAssets(uint256 _amount) internal override returns (uint256 withdrawAmount) {
        require(tokenDelegator.redeemUnderlying(_amount) == 0, "BenqiLendingStrategy::failed to redeem");
        return _amount;
    }

    function _rollupDebt() internal override {
        uint256 borrowed = tokenDelegator.borrowBalanceCurrent(address(this));
        uint256 principal = tokenDelegator.balanceOfUnderlying(address(this));
        (uint256 borrowLimit, uint256 borrowBips) = _getBorrowLimit();
        uint256 supplied = principal;
        uint256 lendTarget = ((principal - borrowed) * leverageLevel) / leverageBips;
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
            require(tokenDelegator.borrow(toBorrowAmount) == 0, "BenqiStrategyV4::borrowing failed");
            require(tokenDelegator.mint(toBorrowAmount) == 0, "BenqiStrategyV4::lending failed");
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
            require(tokenDelegator.redeemUnderlying(unrollAmount) == 0, "BenqiStrategyV4::failed to redeem");
            require(tokenDelegator.repayBorrow(unrollAmount) == 0, "BenqiStrategyV4::failed to repay borrow");
            balance = tokenDelegator.balanceOfUnderlying(address(this));
            borrowed = tokenDelegator.borrowBalanceCurrent(address(this));
            if (targetBorrow >= borrowed) {
                break;
            }
            toRepay = borrowed - targetBorrow;
        }
        depositToken.approve(address(tokenDelegator), 0);
    }

    function _getBorrowLimit() internal view returns (uint256, uint256) {
        (, uint256 borrowLimit) = comptroller.markets(address(tokenDelegator));
        return (borrowLimit, 1e18);
    }

    function _getRedeemable(uint256 balance, uint256 borrowed, uint256 borrowLimit, uint256 bips)
        internal
        view
        returns (uint256)
    {
        return (((balance - ((borrowed * bips) / borrowLimit)) * redeemLimitSafetyMargin)) / leverageBips;
    }

    function _getBorrowable(uint256 balance, uint256 borrowed, uint256 borrowLimit, uint256 bips)
        internal
        pure
        returns (uint256)
    {
        return ((balance * borrowLimit) / bips) - borrowed;
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        Reward[] memory pendingRewards = new Reward[](2);
        pendingRewards[0] =
            Reward({reward: QI, amount: BenqiLibrary.calculateReward(comptroller, tokenDelegator, 0, address(this))});
        pendingRewards[1] = Reward({
            reward: address(WGAS),
            amount: BenqiLibrary.calculateReward(comptroller, tokenDelegator, 1, address(this))
        });
        return pendingRewards;
    }

    function _getRewards() internal override {
        address[] memory markets = new address[](1);
        markets[0] = address(tokenDelegator);
        comptroller.claimReward(0, address(this), markets);
        comptroller.claimReward(1, address(this), markets);
    }

    receive() external payable {
        require(msg.sender == address(comptroller), "BenqiStrategyV4::Not allowed");
    }

    function totalDeposits() public view override returns (uint256) {
        (, uint256 internalBalance, uint256 borrow, uint256 exchangeRate) =
            tokenDelegator.getAccountSnapshot(address(this));
        return ((internalBalance * exchangeRate) / 1e18) - borrow;
    }

    function _emergencyWithdraw() internal override {
        uint256 borrowed = tokenDelegator.borrowBalanceCurrent(address(this));
        uint256 balance = tokenDelegator.balanceOfUnderlying(address(this));
        _unrollDebt(balance - borrowed);
        tokenDelegator.redeemUnderlying(tokenDelegator.balanceOfUnderlying(address(this)));
    }
}
