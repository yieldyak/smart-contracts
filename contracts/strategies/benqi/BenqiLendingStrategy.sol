// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../LendingStrategy.sol";
import "../../lib/SafeMath.sol";

import "./interfaces/IBenqiUnitroller.sol";
import "./interfaces/IBenqiERC20Delegator.sol";
import "./interfaces/IBenqiLibrary.sol";

contract BenqiLendingStrategy is LendingStrategy {
    using SafeMath for uint256;

    struct LeverageSettings {
        uint256 leverageLevel;
        uint256 leverageBips;
        uint256 minMinting;
    }

    address private constant QI = 0x8729438EB15e2C8B576fCc6AeCdA6A148776C0F5;

    uint256 public redeemLimitSafetyMargin;
    uint256 public minMinting;
    uint256 public maxPreviewInaccuracyBips;

    IBenqiUnitroller private rewardController;
    IBenqiERC20Delegator private tokenDelegator;
    IBenqiLibrary private benqiLibrary;

    constructor(
        address _rewardController,
        address _tokenDelegator,
        address _benqiLibrary,
        uint256 _maxPreviewInaccuracyBips,
        LeverageSettings memory _leverageSettings,
        address _swapPairDepositToken,
        RewardSwapPairs[] memory _rewardSwapPairs,
        BaseSettings memory _baseSettings,
        StrategySettings memory _strategySettings
    )
        LendingStrategy(
            _leverageSettings.leverageLevel,
            _leverageSettings.leverageBips,
            _swapPairDepositToken,
            _rewardSwapPairs,
            _baseSettings,
            _strategySettings
        )
    {
        rewardController = IBenqiUnitroller(_rewardController);
        tokenDelegator = IBenqiERC20Delegator(_tokenDelegator);
        benqiLibrary = IBenqiLibrary(_benqiLibrary);

        maxPreviewInaccuracyBips = _maxPreviewInaccuracyBips;

        minMinting = _leverageSettings.minMinting;
        _updateLeverage(
            _leverageSettings.leverageLevel,
            _leverageSettings.leverageBips,
            _leverageSettings.leverageBips.mul(990).div(1000)
        );
    }

    /*//////////////////////////////////////////////////////////////
                                DEPOSIT
    //////////////////////////////////////////////////////////////*/

    function _getMaxPreviewInaccuracyBips() internal view override returns (uint256) {
        return maxPreviewInaccuracyBips;
    }

    function beforeDeposit() internal override {
        tokenDelegator.accrueInterest();
    }

    function _supplyAssets(uint256 _amount) internal override {
        IERC20(asset).approve(address(tokenDelegator), _amount);
        require(tokenDelegator.mint(_amount) == 0, "BenqiLendingStrategy::Deposit failed");
        IERC20(asset).approve(address(tokenDelegator), 0);
    }

    /*//////////////////////////////////////////////////////////////
                              WITHDRAW
    //////////////////////////////////////////////////////////////*/

    function beforeWithdraw() internal override {
        tokenDelegator.accrueInterest();
    }

    function _withdrawAssets(uint256 _amount) internal override returns (uint256 _withdrawAmount) {
        require(tokenDelegator.redeemUnderlying(_amount) == 0, "BenqiLendingStrategy::failed to redeem");
        return _amount;
    }

    /*//////////////////////////////////////////////////////////////
                              LENDING
    //////////////////////////////////////////////////////////////*/

    function _rollupDebt() internal override {
        uint256 borrowed = tokenDelegator.borrowBalanceCurrent(address(this));
        uint256 supplied = tokenDelegator.balanceOfUnderlying(address(this));
        (uint256 borrowLimit, uint256 borrowBips) = _getBorrowLimit();
        uint256 lendTarget = supplied.sub(borrowed).mul(leverageLevel).div(leverageBips);
        uint256 totalBorrowed = borrowed;
        IERC20(asset).approve(address(tokenDelegator), lendTarget);
        while (supplied < lendTarget) {
            uint256 toBorrowAmount = _getBorrowable(supplied, totalBorrowed, borrowLimit, borrowBips);
            if (supplied.add(toBorrowAmount) > lendTarget) {
                toBorrowAmount = lendTarget.sub(supplied);
            }
            // safeguard needed because we can't mint below a certain threshold
            if (toBorrowAmount < minMinting) {
                break;
            }
            require(tokenDelegator.borrow(toBorrowAmount) == 0, "BenqiLendingStrategy::borrowing failed");
            require(tokenDelegator.mint(toBorrowAmount) == 0, "BenqiLendingStrategy::lending failed");
            supplied = tokenDelegator.balanceOfUnderlying(address(this));
            totalBorrowed = totalBorrowed.add(toBorrowAmount);
        }
        IERC20(asset).approve(address(tokenDelegator), 0);
    }

    function _getRedeemable(
        uint256 balance,
        uint256 borrowed,
        uint256 borrowLimit,
        uint256 bips
    ) internal view returns (uint256) {
        return balance.sub(borrowed.mul(bips).div(borrowLimit)).mul(redeemLimitSafetyMargin).div(leverageBips);
    }

    function _getBorrowable(
        uint256 balance,
        uint256 borrowed,
        uint256 borrowLimit,
        uint256 bips
    ) internal pure returns (uint256) {
        return balance.mul(borrowLimit).div(bips).sub(borrowed);
    }

    function _getBorrowLimit() internal view returns (uint256, uint256) {
        (, uint256 borrowLimit) = rewardController.markets(address(tokenDelegator));
        return (borrowLimit, 1e18);
    }

    function _unrollDebt(uint256 _amountToFreeUp) internal override {
        uint256 borrowed = tokenDelegator.borrowBalanceCurrent(address(this));
        uint256 balance = tokenDelegator.balanceOfUnderlying(address(this));
        uint256 targetBorrow = balance.sub(borrowed).sub(_amountToFreeUp).mul(leverageLevel).div(leverageBips).sub(
            balance.sub(borrowed).sub(_amountToFreeUp)
        );
        uint256 toRepay = borrowed.sub(targetBorrow);
        (uint256 borrowLimit, uint256 borrowBips) = _getBorrowLimit();
        IERC20(asset).approve(address(tokenDelegator), borrowed);
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
            toRepay = borrowed.sub(targetBorrow);
        }
        IERC20(asset).approve(address(tokenDelegator), 0);
    }

    function _updateLeverage(
        uint256 _leverageLevel,
        uint256 _leverageBips,
        uint256 _redeemLimitSafetyMargin
    ) internal {
        leverageLevel = _leverageLevel;
        leverageBips = _leverageBips;
        redeemLimitSafetyMargin = _redeemLimitSafetyMargin;
    }

    function getActualLeverage() public view returns (uint256) {
        (, uint256 internalBalance, uint256 borrow, uint256 exchangeRate) = tokenDelegator.getAccountSnapshot(
            address(this)
        );
        uint256 balance = internalBalance.mul(exchangeRate).div(1e18);
        return balance.mul(1e18).div(balance.sub(borrow));
    }

    /*//////////////////////////////////////////////////////////////
                              REINVEST
    //////////////////////////////////////////////////////////////*/

    function _pendingRewards() internal view override returns (Reward[] memory) {
        uint256 qiRewards = benqiLibrary.calculateReward(
            address(rewardController),
            address(tokenDelegator),
            0,
            address(this)
        );
        uint256 avaxRewards = benqiLibrary.calculateReward(
            address(rewardController),
            address(tokenDelegator),
            1,
            address(this)
        );

        Reward[] memory pendingRewards = new Reward[](2);
        pendingRewards[0] = Reward({reward: address(WAVAX), amount: avaxRewards});
        pendingRewards[1] = Reward({reward: QI, amount: qiRewards});

        return pendingRewards;
    }

    function _getRewards() internal override {
        address[] memory markets = new address[](1);
        markets[0] = address(tokenDelegator);
        rewardController.claimReward(0, address(this), markets);
        rewardController.claimReward(1, address(this), markets);
    }

    receive() external payable {
        require(msg.sender == address(rewardController), "BenqiStrategyV3::payments not allowed");
    }

    /*//////////////////////////////////////////////////////////////
                                ACCOUNTING 
    //////////////////////////////////////////////////////////////*/

    function totalAssets() public view override returns (uint256) {
        (, uint256 internalBalance, uint256 borrow, uint256 exchangeRate) = tokenDelegator.getAccountSnapshot(
            address(this)
        );
        return internalBalance.mul(exchangeRate).div(1e18).sub(borrow);
    }

    /*//////////////////////////////////////////////////////////////
                                EMERGENCY 
    //////////////////////////////////////////////////////////////*/

    function _emergencyWithdraw() internal override {
        uint256 borrowed = tokenDelegator.borrowBalanceCurrent(address(this));
        uint256 balance = tokenDelegator.balanceOfUnderlying(address(this));
        _unrollDebt(balance.sub(borrowed));
        tokenDelegator.redeemUnderlying(tokenDelegator.balanceOfUnderlying(address(this)));
    }

    /*//////////////////////////////////////////////////////////////
                                 ADMIN
    //////////////////////////////////////////////////////////////*/

    function updateLeverage(
        uint256 _leverageLevel,
        uint256 _leverageBips,
        uint256 _redeemLimitSafetyMargin
    ) external onlyDev {
        _updateLeverage(_leverageLevel, _leverageBips, _redeemLimitSafetyMargin);
        uint256 borrowed = tokenDelegator.borrowBalanceCurrent(address(this));
        uint256 balance = tokenDelegator.balanceOfUnderlying(address(this));
        _unrollDebt(balance.sub(borrowed));
        if (balance.sub(borrowed) > 0) {
            _rollupDebt();
        }
    }

    function updateMaxPreviewInaccuracy(uint256 _maxPreviewInaccuracyBips) public onlyDev {
        maxPreviewInaccuracyBips = _maxPreviewInaccuracyBips;
    }
}
