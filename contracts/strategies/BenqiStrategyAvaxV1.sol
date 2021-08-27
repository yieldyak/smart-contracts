// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "../YakStrategyV2Payable.sol";
import "../interfaces/IBenqiUnitroller.sol";
import "../interfaces/IBenqiAVAXDelegator.sol";
import "../interfaces/IWAVAX.sol";

import "../interfaces/IERC20.sol";
import "../lib/DexLibrary.sol";
import "../lib/ReentrancyGuard.sol";

contract BenqiStrategyAvaxV1 is YakStrategyV2Payable, ReentrancyGuard {
    using SafeMath for uint;

    IBenqiUnitroller private rewardController;
    IBenqiAVAXDelegator private tokenDelegator;
    IERC20 private rewardToken0;
    IPair private swapPairToken0; // swaps rewardToken0 to WAVAX
    IWAVAX private constant WAVAX = IWAVAX(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);
    uint private leverageLevel;
    uint private leverageBips;
    uint private minMinting;

    constructor (
        string memory _name,
        address _rewardController,
        address _tokenDelegator,
        address _rewardToken0,
        address _swapPairToken0,
        address _timelock,
        uint _minMinting,
        uint _leverageLevel,
        uint _leverageBips,
        uint _minTokensToReinvest,
        uint _adminFeeBips,
        uint _devFeeBips,
        uint _reinvestRewardBips
    ) {
        name = _name;
        depositToken = IERC20(address(0));
        rewardController = IBenqiUnitroller(_rewardController);
        tokenDelegator = IBenqiAVAXDelegator(_tokenDelegator);
        rewardToken0 = IERC20(_rewardToken0);
        rewardToken = IERC20(address(WAVAX));
        minMinting = _minMinting;
        _updateLeverage(_leverageLevel, _leverageBips);
        devAddr = msg.sender;

        _enterMarket();

        assignSwapPairSafely(_swapPairToken0);
        setAllowances();
        updateMinTokensToReinvest(_minTokensToReinvest);
        updateAdminFee(_adminFeeBips);
        updateDevFee(_devFeeBips);
        updateReinvestReward(_reinvestRewardBips);
        updateDepositsEnabled(true);
        transferOwnership(_timelock);

        emit Reinvest(0, 0);
    }

    function totalDeposits() public override view returns (uint) {
        (, uint256 internalBalance, uint borrow, uint256 exchangeRate) = tokenDelegator.getAccountSnapshot(address(this));
        return internalBalance.mul(exchangeRate).div(1e18).sub(borrow);
    }

    function _totalDepositsFresh() internal returns (uint) {
        uint borrow = tokenDelegator.borrowBalanceCurrent(address(this));
        uint balance = tokenDelegator.balanceOfUnderlying(address(this));
        return balance.sub(borrow);
    }

    function _enterMarket() internal {
        address[] memory tokens = new address[](1);
        tokens[0] = address(tokenDelegator);
        rewardController.enterMarkets(tokens);
    }

    function _updateLeverage(uint _leverageLevel, uint _leverageBips) internal {
        leverageLevel = _leverageLevel;
        leverageBips = _leverageBips;
    }

    function updateLeverage(uint _leverageLevel, uint _leverageBips) external onlyDev {
        _updateLeverage(_leverageLevel, _leverageBips);
        _unrollDebt();
        uint balance = tokenDelegator.balanceOfUnderlying(address(this));
        if (balance > 0) {
            _rollupDebt(balance, 0);
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

    function setAllowances() public override onlyOwner {
        tokenDelegator.approve(address(tokenDelegator), type(uint256).max);
    }

    function deposit() external payable override nonReentrant {
         _deposit(msg.sender, msg.value);
    }

    function depositFor(address account) external payable override nonReentrant {
         _deposit(account, msg.value);
    }

    function deposit(uint amount) external override {
        revert();
    }

    function depositWithPermit(uint amount, uint deadline, uint8 v, bytes32 r, bytes32 s) external override {
        revert();
    }

    function depositFor(address account, uint amount) external override {
        revert();
    }

    function _deposit(address account, uint amount) private onlyAllowedDeposits {
        require(DEPOSITS_ENABLED == true, "BenqiStrategyV1::_deposit");
        if (MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST > 0) {
            (uint qiRewards, uint avaxRewards, uint totalAvaxRewards) = _checkRewards();
            if (totalAvaxRewards > MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST) {
                _reinvest(qiRewards, avaxRewards, totalAvaxRewards);
            }
        }
        uint depositTokenAmount = amount;
        uint balance = _totalDepositsFresh();
        if (totalSupply.mul(balance) > 0) {
            depositTokenAmount = amount.mul(totalSupply).div(balance);
        }
        _mint(account, depositTokenAmount);
        _stakeDepositTokens(amount);
        emit Deposit(account, amount);
    }

    function withdraw(uint amount) external override nonReentrant {
        require(amount > minMinting, "BenqiStrategyV1::below minimum withdraw");
        uint depositTokenAmount = _totalDepositsFresh().mul(amount).div(totalSupply);
        if (depositTokenAmount > 0) {
            _burn(msg.sender, amount);
            _withdrawDepositTokens(depositTokenAmount);
            (bool success, ) = msg.sender.call{value: depositTokenAmount}("");
            require(success, "BenqiStrategyV1::withdraw transfer failed");
            emit Withdraw(msg.sender, depositTokenAmount);
        }
    }

    function _withdrawDepositTokens(uint amount) private {
        _unrollDebt();
        require(tokenDelegator.redeemUnderlying(amount) == 0, "BenqiStrategyV1::redeem failed");
        uint balance = tokenDelegator.balanceOfUnderlying(address(this));
        if (balance > 0) {
            _rollupDebt(balance, 0);
        }
    }

    function reinvest() external override onlyEOA nonReentrant {
        (uint qiRewards, uint avaxRewards, uint totalAvaxRewards) = _checkRewards();
        require(totalAvaxRewards >= MIN_TOKENS_TO_REINVEST, "BenqiStrategyV1::reinvest");
        _reinvest(qiRewards, avaxRewards, totalAvaxRewards);
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
     * @param amount deposit tokens to reinvest
     */
    function _reinvest(uint qiRewards, uint avaxRewards, uint amount) private {
        rewardController.claimReward(0, address(this));
        rewardController.claimReward(1, address(this));
    
        if (qiRewards > 0) {
            uint convertedWavax = DexLibrary.swap(qiRewards, address(rewardToken0), address(WAVAX), swapPairToken0);
            WAVAX.withdraw(convertedWavax);
        }

        amount = address(this).balance;

        uint devFee = amount.mul(DEV_FEE_BIPS).div(BIPS_DIVISOR);
        uint adminFee = amount.mul(ADMIN_FEE_BIPS).div(BIPS_DIVISOR);
        uint reinvestFee = amount.mul(REINVEST_REWARD_BIPS).div(BIPS_DIVISOR);
        WAVAX.deposit{value: devFee.add(adminFee).add(reinvestFee)}();
        if (devFee > 0) {
            _safeTransfer(address(rewardToken), devAddr, devFee);
        }
        if (adminFee > 0) {
            _safeTransfer(address(rewardToken), owner(), adminFee);
        }
        if (reinvestFee > 0) {
            _safeTransfer(address(rewardToken), msg.sender, reinvestFee);
        }

        _stakeDepositTokens(amount.sub(devFee).sub(adminFee).sub(reinvestFee));

        emit Reinvest(totalDeposits(), totalSupply);
    }

    function _rollupDebt(uint principal, uint borrowed) internal {
        (uint borrowLimit, uint borrowBips) = _getBorrowLimit();
        uint supplied = principal;
        uint lendTarget = principal.sub(borrowed).mul(leverageLevel).div(leverageBips);
        uint totalBorrowed = borrowed;
        while(supplied < lendTarget) {
            uint toBorrowAmount = _getBorrowable(supplied, totalBorrowed, borrowLimit, borrowBips);
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

    function _getRedeemable(uint balance, uint borrowed, uint borrowLimit, uint bips) internal pure returns (uint256) {
        return balance.sub(borrowed.mul(bips).div(borrowLimit));
    }

    function _getBorrowable(uint balance, uint borrowed, uint borrowLimit, uint bips) internal pure returns (uint256) {
        return balance.mul(borrowLimit).div(bips).sub(borrowed);
    }

    function _getBorrowLimit() internal view returns (uint, uint) {
        (, uint borrowLimit) = rewardController.markets(address(tokenDelegator));
        return (borrowLimit, 1e18);
    }

    function _unrollDebt() internal {
        uint borrowed = tokenDelegator.borrowBalanceCurrent(address(this));
        uint balance = tokenDelegator.balanceOfUnderlying(address(this));
        (uint borrowLimit, uint borrowBips) = _getBorrowLimit();

        while(borrowed > 0) {
            uint unrollAmount = _getRedeemable(balance, borrowed, borrowLimit, borrowBips);
            if (unrollAmount > borrowed) {
                unrollAmount = borrowed;
            }
            require(tokenDelegator.redeemUnderlying(unrollAmount) == 0, "BenqiStrategyV1::failed to redeem");
            tokenDelegator.repayBorrow{value: unrollAmount}();
            balance = balance.sub(unrollAmount);
            borrowed = borrowed.sub(unrollAmount);
        }
    }

    function _stakeDepositTokens(uint amount) private {
        require(amount > 0, "BenqiStrategyV1::_stakeDepositTokens");
        tokenDelegator.mint{value: amount}();
        uint borrowed = tokenDelegator.borrowBalanceCurrent(address(this));
        uint principal = tokenDelegator.balanceOfUnderlying(address(this));
        _rollupDebt(principal, borrowed);
    }

    /**
     * @notice Safely transfer using an anonymosu ERC20 token
     * @dev Requires token to return true on transfer
     * @param token address
     * @param to recipient address
     * @param value amount
     */
    function _safeTransfer(address token, address to, uint256 value) private {
        require(IERC20(token).transfer(to, value), 'BenqiStrategyV1::TRANSFER_FROM_FAILED');
    }

    function _checkRewards() internal view returns (uint qiAmount, uint avaxAmount, uint totalAvaxAmount) {
        uint qiRewards = _getReward(0, address(this));
        uint avaxRewards = _getReward(1, address(this));

        uint qiAsWavax = DexLibrary.estimateConversionThroughPair(
            qiRewards, address(rewardToken0),
            address(WAVAX), swapPairToken0
        );
        return (qiRewards, avaxRewards, avaxRewards.add(qiAsWavax));
    }

    function checkReward() public override view returns (uint) {
        (,,uint avaxRewards) = _checkRewards();
        return avaxRewards;
    }

    function _getReward(uint8 tokenIndex, address account) internal view returns (uint) {
        uint rewardAccrued = rewardController.rewardAccrued(tokenIndex, account);
        (uint224 supplyIndex, ) = rewardController.rewardSupplyState(tokenIndex, account);
        uint supplierIndex = rewardController.rewardSupplierIndex(tokenIndex, address(tokenDelegator), account);
        uint supplyIndexDelta = 0;
        if (supplyIndex > supplierIndex) {
            supplyIndexDelta = supplyIndex - supplierIndex; 
        }
        uint supplyAccrued = tokenDelegator.balanceOf(account).mul(supplyIndexDelta);
        (uint224 borrowIndex, ) = rewardController.rewardBorrowState(tokenIndex, account);
        uint borrowerIndex = rewardController.rewardBorrowerIndex(tokenIndex, address(tokenDelegator), account);
        uint borrowIndexDelta = 0;
        if (borrowIndex > borrowerIndex) {
            borrowIndexDelta = borrowIndex - borrowerIndex;
        }
        uint borrowAccrued = tokenDelegator.borrowBalanceStored(account).mul(borrowIndexDelta);
        return rewardAccrued.add(supplyAccrued.sub(borrowAccrued));
    }

    function getActualLeverage() public view returns (uint) {
        (, uint256 internalBalance, uint256 borrow, uint256 exchangeRate) = tokenDelegator.getAccountSnapshot(address(this));
        uint balance = internalBalance.mul(exchangeRate).div(1e18);
        return balance.mul(1e18).div(balance.sub(borrow));
    }

    function estimateDeployedBalance() external override view returns (uint) {
        return totalDeposits();
    }

    function rescueDeployedFunds(uint minReturnAmountAccepted, bool disableDeposits) external override onlyOwner {
        uint balanceBefore = depositToken.balanceOf(address(this));
        _unrollDebt();
        tokenDelegator.redeemUnderlying(tokenDelegator.balanceOfUnderlying(address(this)));
        uint balanceAfter = depositToken.balanceOf(address(this));
        require(balanceAfter.sub(balanceBefore) >= minReturnAmountAccepted, "BenqiStrategyV1::rescueDeployedFunds");
        emit Reinvest(totalDeposits(), totalSupply);
        if (DEPOSITS_ENABLED == true && disableDeposits == true) {
            updateDepositsEnabled(false);
        }
    }
}

