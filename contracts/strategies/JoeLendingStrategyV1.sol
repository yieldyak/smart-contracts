// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "../YakStrategyV2.sol";
import "../interfaces/IJoetroller.sol";
import "../interfaces/IJoeRewardDistributor.sol";
import "../interfaces/IJoeERC20Delegator.sol";
import "../interfaces/IWAVAX.sol";

import "../interfaces/IERC20.sol";
import "../lib/DexLibrary.sol";

/**
 * @title Strategy for Banker Joe ERC20
 * @dev Bank Joe emits rewards in AVAX and ERC20. During AVAX claim, contract becomes gas bound
 */
contract JoeLendingStrategyV1 is YakStrategyV2 {
    using SafeMath for uint256;

    IJoetroller private rewardController;
    IJoeERC20Delegator private tokenDelegator; // jDAI
    IERC20 private rewardToken0; // JOE
    IERC20 private rewardToken1; // AVAX
    IPair private swapPairToken0; // JOE-AVAX
    IPair private swapPairToken1; // AVAX-DAI
    IWAVAX private constant WAVAX = IWAVAX(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);
    uint256 private leverageLevel;
    uint256 private leverageBips;
    uint256 private minMinting;

    constructor(
        string memory _name,
        address _depositToken,
        address _rewardController,
        address _tokenDelegator,
        address _rewardToken0,
        address _rewardToken1,
        address _swapPairToken0,
        address _swapPairToken1,
        address _timelock,
        uint256 _minMinting,
        uint256 _leverageLevel,
        uint256 _leverageBips,
        uint256 _minTokensToReinvest,
        uint256 _adminFeeBips,
        uint256 _devFeeBips,
        uint256 _reinvestRewardBips
    ) {
        name = _name;
        depositToken = IERC20(_depositToken);
        rewardController = IJoetroller(_rewardController);
        tokenDelegator = IJoeERC20Delegator(_tokenDelegator);
        rewardToken0 = IERC20(_rewardToken0);
        rewardToken1 = IERC20(_rewardToken1);
        rewardToken = rewardToken1;
        minMinting = _minMinting;
        _updateLeverage(_leverageLevel, _leverageBips);
        devAddr = msg.sender;

        _enterMarket();

        assignSwapPairSafely(_swapPairToken0, _swapPairToken1);
        setAllowances();
        updateMinTokensToReinvest(_minTokensToReinvest);
        updateAdminFee(_adminFeeBips);
        updateDevFee(_devFeeBips);
        updateReinvestReward(_reinvestRewardBips);
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

    function _updateLeverage(uint256 _leverageLevel, uint256 _leverageBips) internal {
        leverageLevel = _leverageLevel;
        leverageBips = _leverageBips;
    }

    function updateLeverage(uint256 _leverageLevel, uint256 _leverageBips) external onlyDev {
        _updateLeverage(_leverageLevel, _leverageBips);
        uint256 balance = _totalDepositsFresh();
        _unrollDebt(balance);
        if (balance > 0) {
            _rollupDebt(balance, 0);
        }
    }

    /**
     * @notice Initialization helper for Pair deposit tokens
     * @dev Checks that selected Pairs are valid for trading deposit tokens
     * @dev Assigns values to swapPairToken0 and swapPairToken1
     */
    function assignSwapPairSafely(address _swapPairToken0, address _swapPairToken1) private {
        require(_swapPairToken0 > address(0), "Swap pair 0 is necessary but not supplied");
        require(_swapPairToken1 > address(0), "Swap pair 1 is necessary but not supplied");

        require(
            address(rewardToken0) == IPair(address(_swapPairToken0)).token0() ||
                address(rewardToken0) == IPair(address(_swapPairToken0)).token1(),
            "Swap pair 0 does not match rewardToken0"
        );

        require(
            address(rewardToken1) == IPair(address(_swapPairToken0)).token0() ||
                address(rewardToken1) == IPair(address(_swapPairToken0)).token1(),
            "Swap pair 0 does not match rewardToken1"
        );

        require(
            address(depositToken) == IPair(address(_swapPairToken1)).token0() ||
                address(depositToken) == IPair(address(_swapPairToken1)).token1(),
            "Swap pair 1 does not match depositToken"
        );

        require(
            address(rewardToken1) == IPair(address(_swapPairToken1)).token0() ||
                address(rewardToken1) == IPair(address(_swapPairToken1)).token1(),
            "Swap pair 1 does not match rewardToken1"
        );

        swapPairToken0 = IPair(_swapPairToken0);
        swapPairToken1 = IPair(_swapPairToken1);
    }

    function setAllowances() public override onlyOwner {
        depositToken.approve(address(tokenDelegator), type(uint256).max);
        tokenDelegator.approve(address(tokenDelegator), type(uint256).max);
    }

    function deposit(uint256 amount) external override {
        _deposit(msg.sender, amount);
    }

    function depositWithPermit(
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {
        depositToken.permit(msg.sender, address(this), amount, deadline, v, r, s);
        _deposit(msg.sender, amount);
    }

    function depositFor(address account, uint256 amount) external override {
        _deposit(account, amount);
    }

    function _deposit(address account, uint256 amount) private onlyAllowedDeposits {
        require(DEPOSITS_ENABLED == true, "JoeLendingStrategyV1::_deposit");
        if (MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST > 0) {
            (uint256 joeRewards, uint256 avaxBalance, uint256 amountToReinvest) = _checkRewards();
            if (amountToReinvest > MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST) {
                _reinvest(joeRewards, avaxBalance, amountToReinvest);
            }
        }
        require(depositToken.transferFrom(msg.sender, address(this), amount), "JoeLendingStrategyV1::transfer failed");
        uint256 shareTokenAmount = amount;
        uint256 balance = _totalDepositsFresh();
        if (totalSupply.mul(balance) > 0) {
            shareTokenAmount = amount.mul(totalSupply).div(balance);
        }
        _mint(account, shareTokenAmount);
        _stakeDepositTokens(amount);
        emit Deposit(account, amount);
        claimAVAXRewards();
    }

    function withdraw(uint256 amount) external override {
        uint256 depositTokenAmount = _totalDepositsFresh().mul(amount).div(totalSupply);
        require(depositTokenAmount >= minMinting, "JoeLendingStrategyV1:: below minimum withdraw");
        _burn(msg.sender, amount);
        _withdrawDepositTokens(depositTokenAmount);
        _safeTransfer(address(depositToken), msg.sender, depositTokenAmount);
        emit Withdraw(msg.sender, depositTokenAmount);
        claimAVAXRewards();
    }

    function _withdrawDepositTokens(uint256 amount) private {
        _unrollDebt(amount);
        require(tokenDelegator.redeemUnderlying(amount) == 0, "JoeLendingStrategyV1::redeem failed");
        uint256 balance = tokenDelegator.balanceOfUnderlying(address(this));
        uint256 borrow = tokenDelegator.borrowBalanceCurrent(address(this));
        if (balance > 0) {
            _rollupDebt(balance, borrow);
        }
    }

    function reinvest() external override onlyEOA {
        (uint256 joeRewards, uint256 avaxBalance, uint256 amountToReinvest) = _checkRewards();
        require(amountToReinvest >= MIN_TOKENS_TO_REINVEST, "JoeLendingStrategyV1::reinvest");
        _reinvest(joeRewards, avaxBalance, amountToReinvest);
        claimAVAXRewards();
    }

    receive() external payable {
        require(msg.sender == address(rewardController), "JoeLendingStrategyV1::payments not allowed");
    }

    /**
     * @notice Reinvest rewards from staking contract to deposit tokens
     * @dev Reverts if the expected amount of tokens are not returned from `stakingContract`
     * @param joeRewards amount of JOE tokens to reinvest
     * @param avaxBalance amount of AVAX to reinvest
     * @param amount total amount of reward tokens to reinvest
     */
    function _reinvest(
        uint256 joeRewards,
        uint256 avaxBalance,
        uint256 amount
    ) private {
        if (joeRewards > 0) {
            rewardController.claimReward(0, address(this));
            DexLibrary.swap(joeRewards, address(rewardToken0), address(rewardToken1), swapPairToken0);
        }

        if (avaxBalance > 0) {
            WAVAX.deposit{value: avaxBalance}();
        }

        uint256 devFee = amount.mul(DEV_FEE_BIPS).div(BIPS_DIVISOR);
        if (devFee > 0) {
            _safeTransfer(address(rewardToken), devAddr, devFee);
        }

        uint256 adminFee = amount.mul(ADMIN_FEE_BIPS).div(BIPS_DIVISOR);
        if (adminFee > 0) {
            _safeTransfer(address(rewardToken), owner(), adminFee);
        }

        uint256 reinvestFee = amount.mul(REINVEST_REWARD_BIPS).div(BIPS_DIVISOR);
        if (reinvestFee > 0) {
            _safeTransfer(address(rewardToken), msg.sender, reinvestFee);
        }

        uint256 depositTokenAmount = DexLibrary.swap(
            amount.sub(devFee).sub(adminFee).sub(reinvestFee),
            address(rewardToken1),
            address(depositToken),
            swapPairToken1
        );

        _stakeDepositTokens(depositTokenAmount);

        emit Reinvest(totalDeposits(), totalSupply);
    }

    /**
     * @notice Claims AVAX rewards on behalf of strategy
     * @dev Contract becomes gas bound here
     * @dev Conditional for gas savings on repeat actions
     * @dev Public permission in case of stuck state
     */
    function claimAVAXRewards() public {
        if (DEPOSITS_ENABLED == true) {
            if (_getReward(1, address(this)) >= MIN_TOKENS_TO_REINVEST) {
                rewardController.claimReward(1, address(this));
            }
        }
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
            require(tokenDelegator.borrow(toBorrowAmount) == 0, "JoeLendingStrategyV1::borrowing failed");
            require(tokenDelegator.mint(toBorrowAmount) == 0, "JoeLendingStrategyV1::lending failed");
            supplied = tokenDelegator.balanceOfUnderlying(address(this));
            totalBorrowed = totalBorrowed.add(toBorrowAmount);
        }
    }

    function _getBorrowable(
        uint256 balance,
        uint256 borrowed,
        uint256 borrowLimit,
        uint256 bips
    ) internal pure returns (uint256) {
        return balance.mul(borrowLimit).div(bips).sub(borrowed).mul(950).div(1000);
    }

    function _getBorrowLimit() internal view returns (uint256, uint256) {
        (, uint256 borrowLimit) = rewardController.markets(address(tokenDelegator));
        return (borrowLimit, 1e18);
    }

    function _unrollDebt(uint256 amountToFreeUp) internal {
        uint256 borrowed = tokenDelegator.borrowBalanceCurrent(address(this));
        uint256 balance = tokenDelegator.balanceOfUnderlying(address(this));
        (uint256 borrowLimit, uint256 borrowBips) = _getBorrowLimit();
        uint256 targetBorrow = balance.sub(borrowed).sub(amountToFreeUp).mul(leverageLevel).div(leverageBips).sub(
            balance.sub(borrowed).sub(amountToFreeUp)
        );
        uint256 toRepay = borrowed.sub(targetBorrow);

        while (toRepay > 0) {
            uint256 unrollAmount = _getBorrowable(balance, borrowed, borrowLimit, borrowBips);
            if (unrollAmount > borrowed) {
                unrollAmount = borrowed;
            }
            require(tokenDelegator.redeemUnderlying(unrollAmount) == 0, "JoeLendingStrategyV1::failed to redeem");
            require(tokenDelegator.repayBorrow(unrollAmount) == 0, "JoeLendingStrategyV1::failed to repay borrow");
            balance = tokenDelegator.balanceOfUnderlying(address(this));
            borrowed = borrowed.sub(unrollAmount);
            if (targetBorrow >= borrowed) {
                break;
            }
            toRepay = borrowed.sub(targetBorrow);
        }
    }

    function _stakeDepositTokens(uint256 amount) private {
        require(amount > 0, "JoeLendingStrategyV1::_stakeDepositTokens");
        require(tokenDelegator.mint(amount) == 0, "JoeLendingStrategyV1::Deposit failed");
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
        require(IERC20(token).transfer(to, value), "JoeLendingStrategyV1::TRANSFER_FROM_FAILED");
    }

    /// @notice Returns rewards that can be reinvested
    function _checkRewards()
        internal
        view
        returns (
            uint256 joeRewards,
            uint256 avaxBalance,
            uint256 totalAmount
        )
    {
        uint256 joeRewards = _getReward(0, address(this));
        uint256 wavaxBalance = WAVAX.balanceOf(address(this));
        uint256 avaxBalance = address(this).balance;

        uint256 joeRewardsAsWavax = DexLibrary.estimateConversionThroughPair(
            joeRewards,
            address(rewardToken0),
            address(rewardToken1),
            swapPairToken0
        );
        return (joeRewards, avaxBalance, avaxBalance.add(wavaxBalance).add(joeRewardsAsWavax));
    }

    /**
     * @notice Returns balance available to reinvest
     * @return amount that can be reinvested
     */
    function checkReward() public view override returns (uint256) {
        (, , uint256 totalAmount) = _checkRewards();
        return totalAmount;
    }

    function _getReward(uint8 tokenIndex, address account) internal view returns (uint256) {
        IJoeRewardDistributor rewardDistributor = IJoeRewardDistributor(rewardController.rewardDistributor());
        (uint224 supplyIndex, ) = rewardDistributor.rewardSupplyState(tokenIndex, account);
        uint256 supplierIndex = rewardDistributor.rewardSupplierIndex(tokenIndex, address(tokenDelegator), account);

        uint256 supplyIndexDelta = 0;
        if (supplyIndex > supplierIndex) {
            supplyIndexDelta = supplyIndex - supplierIndex;
        }
        (uint224 borrowIndex, ) = rewardDistributor.rewardBorrowState(tokenIndex, account);
        uint256 borrowerIndex = rewardDistributor.rewardBorrowerIndex(tokenIndex, address(tokenDelegator), account);
        uint256 borrowIndexDelta = 0;
        if (borrowIndex > borrowerIndex) {
            borrowIndexDelta = borrowIndex - borrowerIndex;
        }
        return
            rewardDistributor.rewardAccrued(tokenIndex, account).add(
                tokenDelegator.balanceOf(account).mul(supplyIndexDelta).sub(
                    tokenDelegator.borrowBalanceStored(account).mul(borrowIndexDelta)
                )
            );
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

    function rescueDeployedFunds(uint256 minReturnAmountAccepted, bool disableDeposits) external override onlyOwner {
        uint256 balanceBefore = depositToken.balanceOf(address(this));
        uint256 balance = _totalDepositsFresh();
        _unrollDebt(balance);
        tokenDelegator.redeemUnderlying(balance);
        uint256 balanceAfter = depositToken.balanceOf(address(this));
        require(
            balanceAfter.sub(balanceBefore) >= minReturnAmountAccepted,
            "JoeLendingStrategyV1::rescueDeployedFunds"
        );
        emit Reinvest(totalDeposits(), totalSupply);
        if (DEPOSITS_ENABLED == true && disableDeposits == true) {
            updateDepositsEnabled(false);
        }
    }
}
