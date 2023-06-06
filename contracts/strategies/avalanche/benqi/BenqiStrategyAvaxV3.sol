// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../../YakStrategyV2Payable.sol";
import "../../../lib/DexLibrary.sol";
import "../../../lib/ReentrancyGuard.sol";
import "../../../interfaces/IWGAS.sol";
import "../../../interfaces/IERC20.sol";
import "./interfaces/IBenqiUnitroller.sol";
import "./interfaces/IBenqiAVAXDelegator.sol";
import "./interfaces/IBenqiERC20Delegator.sol";
import "./lib/BenqiLibrary.sol";

contract BenqiStrategyAvaxV3 is YakStrategyV2Payable, ReentrancyGuard {
    using SafeMath for uint256;

    struct LeverageSettings {
        uint256 leverageLevel;
        uint256 leverageBips;
        uint256 minMinting;
    }

    IBenqiUnitroller private rewardController;
    IBenqiAVAXDelegator private tokenDelegator;
    IERC20 private rewardToken0;
    IPair private swapPairToken0; // swaps rewardToken0 to WAVAX
    IWGAS private constant WAVAX = IWGAS(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);
    uint256 private leverageLevel;
    uint256 private leverageBips;
    uint256 private minMinting;
    uint256 private redeemLimitSafetyMargin;

    constructor(
        string memory _name,
        address _rewardController,
        address _tokenDelegator,
        address _rewardToken0,
        address _swapPairToken0,
        address _timelock,
        uint256 _minMinting,
        uint256 _leverageLevel,
        uint256 _leverageBips,
        StrategySettings memory _strategySettings
    ) YakStrategyV2(_strategySettings) {
        name = _name;
        rewardController = IBenqiUnitroller(_rewardController);
        tokenDelegator = IBenqiAVAXDelegator(_tokenDelegator);
        rewardToken0 = IERC20(_rewardToken0);
        minMinting = _minMinting;
        _updateLeverage(
            _leverageLevel,
            _leverageBips,
            _leverageBips.mul(990).div(1000) //works as long as leverageBips > 1000
        );
        devAddr = msg.sender;

        _enterMarket();

        assignSwapPairSafely(_swapPairToken0);
        updateDepositsEnabled(true);
        transferOwnership(_timelock);

        emit Reinvest(0, 0);
    }

    function totalDeposits() public view override returns (uint256) {
        (, uint256 internalBalance, uint256 borrow, uint256 exchangeRate) = tokenDelegator.getAccountSnapshot(
            address(this)
        );
        return internalBalance.mul(exchangeRate).div(1e18).sub(borrow);
    }

    function _totalDepositsFresh() internal returns (uint256) {
        uint256 borrow = tokenDelegator.borrowBalanceCurrent(address(this));
        uint256 balance = tokenDelegator.balanceOfUnderlying(address(this));
        return balance.sub(borrow);
    }

    function _enterMarket() internal {
        address[] memory tokens = new address[](1);
        tokens[0] = address(tokenDelegator);
        rewardController.enterMarkets(tokens);
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

    function updateLeverage(
        uint256 _leverageLevel,
        uint256 _leverageBips,
        uint256 _redeemLimitSafetyMargin
    ) external onlyDev {
        _updateLeverage(_leverageLevel, _leverageBips, _redeemLimitSafetyMargin);
        uint256 balance = tokenDelegator.balanceOfUnderlying(address(this));
        uint256 borrowed = tokenDelegator.borrowBalanceCurrent(address(this));
        _unrollDebt(balance.sub(borrowed));
        if (balance.sub(borrowed) > 0) {
            _rollupDebt(balance.sub(borrowed), 0);
        }
    }

    /**
     * @notice Initialization helper for Pair deposit tokens
     * @dev Checks that selected Pairs are valid for trading deposit tokens
     * @dev Assigns values to swapPairToken0 and swapPairToken1
     */
    function assignSwapPairSafely(address _swapPairToken0) private {
        require(_swapPairToken0 > address(0), "Swap pair 0 is necessary but not supplied");

        require(
            address(rewardToken0) == IPair(address(_swapPairToken0)).token0() ||
                address(rewardToken0) == IPair(address(_swapPairToken0)).token1(),
            "Swap pair 0 does not match rewardToken0"
        );

        require(
            address(WAVAX) == IPair(address(_swapPairToken0)).token0() ||
                address(WAVAX) == IPair(address(_swapPairToken0)).token1(),
            "Swap pair 0 does not match WAVAX"
        );

        swapPairToken0 = IPair(_swapPairToken0);
    }

    function deposit() external payable override nonReentrant {
        _deposit(msg.sender, msg.value);
    }

    function depositFor(address account) external payable override nonReentrant {
        _deposit(account, msg.value);
    }

    function deposit(
        uint256 /*amount*/
    ) external pure override {
        revert();
    }

    function depositWithPermit(
        uint256, /*amount*/
        uint256, /*deadline*/
        uint8, /*v*/
        bytes32, /*r*/
        bytes32 /*s*/
    ) external pure override {
        revert();
    }

    function depositFor(
        address, /*account*/
        uint256 /*amount*/
    ) external pure override {
        revert();
    }

    function _deposit(address account, uint256 amount) private onlyAllowedDeposits {
        require(DEPOSITS_ENABLED == true, "BenqiStrategyV1::_deposit");
        if (MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST > 0) {
            uint256 totalAvaxRewards = checkReward();
            if (totalAvaxRewards > MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST) {
                _reinvest(amount);
            }
        }
        uint256 depositTokenAmount = amount;
        uint256 balance = _totalDepositsFresh();
        if (totalSupply.mul(balance) > 0) {
            depositTokenAmount = amount.mul(totalSupply).div(balance);
        }
        _mint(account, depositTokenAmount);
        _stakeDepositTokens(amount);
        emit Deposit(account, amount);
    }

    function withdraw(uint256 amount) external override nonReentrant {
        require(amount > minMinting, "BenqiStrategyV1::below minimum withdraw");
        uint256 depositTokenAmount = _totalDepositsFresh().mul(amount).div(totalSupply);
        if (depositTokenAmount > 0) {
            _burn(msg.sender, amount);
            _withdrawDepositTokens(depositTokenAmount);
            (bool success, ) = msg.sender.call{value: depositTokenAmount}("");
            require(success, "BenqiStrategyV1::withdraw transfer failed");
            emit Withdraw(msg.sender, depositTokenAmount);
        }
    }

    function _withdrawDepositTokens(uint256 amount) private {
        _unrollDebt(amount);
        require(tokenDelegator.redeemUnderlying(amount) == 0, "BenqiStrategyV2::failed to redeem");
    }

    function reinvest() external override onlyEOA nonReentrant {
        _reinvest(0);
    }

    receive() external payable {
        require(
            msg.sender == address(rewardController) ||
                msg.sender == address(WAVAX) ||
                msg.sender == address(tokenDelegator),
            "BenqiStrategyV1::payments not allowed"
        );
    }

    /**
     * @notice Reinvest rewards from staking contract to deposit tokens
     * @dev Reverts if the expected amount of tokens are not returned from `stakingContract`
     */
    function _reinvest(uint256 userDeposit) private {
        address[] memory markets = new address[](1);
        markets[0] = address(tokenDelegator);
        rewardController.claimReward(0, address(this), markets);
        rewardController.claimReward(1, address(this), markets);

        uint256 avaxBalance = address(this).balance;
        avaxBalance = avaxBalance.sub(userDeposit);
        if (avaxBalance > 0) {
            WAVAX.deposit{value: avaxBalance}();
        }

        uint256 qiBalance = rewardToken0.balanceOf(address(this));
        if (qiBalance > 0) {
            DexLibrary.swap(qiBalance, address(rewardToken0), address(rewardToken), swapPairToken0);
        }

        uint256 amount = rewardToken.balanceOf(address(this));
        if (userDeposit == 0) {
            require(amount >= MIN_TOKENS_TO_REINVEST, "BenqiStrategyV3::reinvest");
        }

        uint256 devFee = amount.mul(DEV_FEE_BIPS).div(BIPS_DIVISOR);
        uint256 reinvestFee = amount.mul(REINVEST_REWARD_BIPS).div(BIPS_DIVISOR);
        if (devFee > 0) {
            _safeTransfer(address(rewardToken), devAddr, devFee);
        }
        if (reinvestFee > 0) {
            _safeTransfer(address(rewardToken), msg.sender, reinvestFee);
        }

        amount = amount.sub(devFee).sub(reinvestFee);
        WAVAX.withdraw(amount);
        _stakeDepositTokens(amount);

        emit Reinvest(totalDeposits(), totalSupply);
    }

    function _rollupDebt(uint256 principal, uint256 borrowed) internal {
        (uint256 borrowLimit, uint256 borrowBips) = _getBorrowLimit();
        uint256 supplied = principal;
        uint256 lendTarget = principal.sub(borrowed).mul(leverageLevel).div(leverageBips);
        uint256 totalBorrowed = borrowed;
        while (supplied < lendTarget) {
            uint256 toBorrowAmount = _getBorrowable(supplied, totalBorrowed, borrowLimit, borrowBips);
            if (supplied.add(toBorrowAmount) > lendTarget) {
                toBorrowAmount = lendTarget.sub(supplied);
            }
            // safeguard needed because we can't mint below a certain threshold
            if (toBorrowAmount < minMinting) {
                break;
            }
            require(tokenDelegator.borrow(toBorrowAmount) == 0, "BenqiStrategyV1::borrowing failed");
            tokenDelegator.mint{value: toBorrowAmount}();
            supplied = tokenDelegator.balanceOfUnderlying(address(this));
            totalBorrowed = totalBorrowed.add(toBorrowAmount);
        }
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

    function _unrollDebt(uint256 amountToBeFreed) internal {
        uint256 borrowed = tokenDelegator.borrowBalanceCurrent(address(this));
        uint256 balance = tokenDelegator.balanceOfUnderlying(address(this));
        uint256 targetBorrow = balance.sub(borrowed).sub(amountToBeFreed).mul(leverageLevel).div(leverageBips).sub(
            balance.sub(borrowed).sub(amountToBeFreed)
        );
        uint256 toRepay = borrowed.sub(targetBorrow);
        (uint256 borrowLimit, uint256 borrowBips) = _getBorrowLimit();
        while (toRepay > 0) {
            uint256 unrollAmount = _getRedeemable(balance, borrowed, borrowLimit, borrowBips);
            if (unrollAmount > toRepay) {
                unrollAmount = toRepay;
            }
            require(tokenDelegator.redeemUnderlying(unrollAmount) == 0, "BenqiStrategyV2::failed to redeem");
            tokenDelegator.repayBorrow{value: unrollAmount}();
            balance = tokenDelegator.balanceOfUnderlying(address(this));
            borrowed = tokenDelegator.borrowBalanceCurrent(address(this));
            if (targetBorrow >= borrowed) {
                break;
            }
            toRepay = borrowed.sub(targetBorrow);
        }
    }

    function _stakeDepositTokens(uint256 amount) private {
        require(amount > 0, "BenqiStrategyV1::_stakeDepositTokens");
        tokenDelegator.mint{value: amount}();
        uint256 borrowed = tokenDelegator.borrowBalanceCurrent(address(this));
        uint256 principal = tokenDelegator.balanceOfUnderlying(address(this));
        _rollupDebt(principal, borrowed);
    }

    /**
     * @notice Safely transfer using an anonymous ERC20 token
     * @dev Requires token to return true on transfer
     * @param token address
     * @param to recipient address
     * @param value amount
     */
    function _safeTransfer(
        address token,
        address to,
        uint256 value
    ) private {
        require(IERC20(token).transfer(to, value), "BenqiStrategyV1::TRANSFER_FROM_FAILED");
    }

    function checkReward() public view override returns (uint256) {
        uint256 qiRewards = BenqiLibrary.calculateReward(
            rewardController,
            IBenqiERC20Delegator(address(tokenDelegator)),
            0,
            address(this)
        );
        uint256 avaxRewards = BenqiLibrary.calculateReward(
            rewardController,
            IBenqiERC20Delegator(address(tokenDelegator)),
            1,
            address(this)
        );

        uint256 qiAsWavax = DexLibrary.estimateConversionThroughPair(
            qiRewards,
            address(rewardToken0),
            address(rewardToken),
            swapPairToken0
        );
        return avaxRewards.add(qiAsWavax);
    }

    function getActualLeverage() public view returns (uint256) {
        (, uint256 internalBalance, uint256 borrow, uint256 exchangeRate) = tokenDelegator.getAccountSnapshot(
            address(this)
        );
        uint256 balance = internalBalance.mul(exchangeRate).div(1e18);
        return balance.mul(1e18).div(balance.sub(borrow));
    }

    function estimateDeployedBalance() external view override returns (uint256) {
        return totalDeposits();
    }

    function rescueDeployedFunds(
        uint256 minReturnAmountAccepted,
        bool /*disableDeposits*/
    ) external override onlyOwner {
        uint256 balanceBefore = address(this).balance;
        uint256 borrowed = tokenDelegator.borrowBalanceCurrent(address(this));
        uint256 balance = tokenDelegator.balanceOfUnderlying(address(this));
        _unrollDebt(balance.sub(borrowed));
        tokenDelegator.redeemUnderlying(balance);
        uint256 balanceAfter = address(this).balance;
        require(balanceAfter.sub(balanceBefore) >= minReturnAmountAccepted, "BenqiStrategyV1::rescueDeployedFunds");
        emit Reinvest(totalDeposits(), totalSupply);
        if (DEPOSITS_ENABLED == true) {
            updateDepositsEnabled(false);
        }
    }
}
