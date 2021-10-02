// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../YakStrategyV2.sol";
import "./interfaces/IBenqiUnitroller.sol";
import "./interfaces/IBenqiERC20Delegator.sol";
import "../../interfaces/IWAVAX.sol";

import "../../interfaces/IERC20.sol";
import "../../lib/SafeERC20.sol";
import "../../lib/DexLibrary.sol";

contract BenqiStrategyQiV1 is YakStrategyV2 {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    IBenqiUnitroller private rewardController;
    IBenqiERC20Delegator private tokenDelegator;
    IERC20 private rewardToken0;
    IERC20 private rewardToken1;
    IPair private swapPairToken0;
    IPair private swapPairToken1;
    IWAVAX private constant WAVAX = IWAVAX(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);
    uint private leverageLevel;
    uint private leverageBips;
    uint private minMinting;

    struct SwapPairs {
        address token0;
        address token1;
    }

    struct RewardTokens {
        address token0;
        address token1;
    }

    constructor (
        string memory _name,
        address _depositToken,
        address _rewardController,
        address _tokenDelegator,
        RewardTokens memory _rewardTokens,
        SwapPairs memory _swapPairs,
        address _timelock,
        uint _minMinting,
        uint _leverageLevel,
        uint _leverageBips,
        StrategySettings memory _strategySettings
    ) {
        name = _name;
        depositToken = IERC20(_depositToken);
        rewardController = IBenqiUnitroller(_rewardController);
        tokenDelegator = IBenqiERC20Delegator(_tokenDelegator);
        rewardToken0 = IERC20(_rewardTokens.token0);
        rewardToken1 = IERC20(_rewardTokens.token1);
        rewardToken = rewardToken0;
        minMinting = _minMinting;
        _updateLeverage(_leverageLevel, _leverageBips);
        devAddr = msg.sender;

        _enterMarket();

        assignSwapPairSafely(_swapPairs);
        setAllowances();
        applyStrategySettings(_strategySettings);
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
    function assignSwapPairSafely(SwapPairs memory _swapPairs) private {
        require(_swapPairs.token0 == address(0), "Swap pair 0 is necessary but not supplied");
        require(_swapPairs.token1 > address(0), "Swap pair 1 is necessary but not supplied");

        require(
            address(depositToken) == IPair(address(_swapPairs.token1)).token0() ||
            address(depositToken) == IPair(address(_swapPairs.token1)).token1(),
            "Swap pair 1 does not match depositToken"
        );

        require(
            address(rewardToken1) == IPair(address(_swapPairs.token1)).token0() ||
            address(rewardToken1) == IPair(address(_swapPairs.token1)).token1(),
            "Swap pair 1 does not match rewardToken1"
        );

        swapPairToken0 = IPair(_swapPairs.token0);
        swapPairToken1 = IPair(_swapPairs.token1);
    }

    function setAllowances() public override onlyOwner {
        depositToken.approve(address(tokenDelegator), type(uint256).max);
        tokenDelegator.approve(address(tokenDelegator), type(uint256).max);
    }

    function deposit(uint amount) external override {
        _deposit(msg.sender, amount);
    }

    function depositWithPermit(uint amount, uint deadline, uint8 v, bytes32 r, bytes32 s) external override {
        depositToken.permit(msg.sender, address(this), amount, deadline, v, r, s);
        _deposit(msg.sender, amount);
    }

    function depositFor(address account, uint amount) external override {
        _deposit(account, amount);
    }

    function _deposit(address account, uint amount) private onlyAllowedDeposits {
        require(DEPOSITS_ENABLED == true, "BenqiStrategyV1::_deposit");
        if (MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST > 0) {
            (/* uint qiRewards */, uint avaxRewards, uint totalQiRewards) = _checkRewards();
            if (totalQiRewards > MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST) {
                _reinvest(avaxRewards, totalQiRewards);
            }
        }
        require(depositToken.transferFrom(msg.sender, address(this), amount), "BenqiStrategyV1::transfer failed");
        uint depositTokenAmount = amount;
        uint balance = _totalDepositsFresh();
        if (totalSupply.mul(balance) > 0) {
            depositTokenAmount = amount.mul(totalSupply).div(balance);
        }
        _mint(account, depositTokenAmount);
        _stakeDepositTokens(amount);
        emit Deposit(account, amount);
    }

    function withdraw(uint amount) external override {
        require(amount > minMinting, "BenqiStrategyV1:: below minimum withdraw");
        uint depositTokenAmount = _totalDepositsFresh().mul(amount).div(totalSupply);
        if (depositTokenAmount > 0) {
            _burn(msg.sender, amount);
            _withdrawDepositTokens(depositTokenAmount);
            IERC20(address(depositToken)).safeTransfer(msg.sender, depositTokenAmount);
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

    function reinvest() external override onlyEOA {
        (/* uint qiRewards */, uint avaxRewards, uint totalQiRewards) = _checkRewards();
        require(totalQiRewards >= MIN_TOKENS_TO_REINVEST, "BenqiStrategyV1::reinvest");
        _reinvest(avaxRewards, totalQiRewards);
    }

    receive() external payable {
        require(msg.sender == address(rewardController), "BenqiStrategyV1::payments not allowed");
    }

    /**
     * @notice Reinvest rewards from staking contract to deposit tokens
     * @dev Reverts if the expected amount of tokens are not returned from `stakingContract`
     * @param amount deposit tokens to reinvest
     */
    function _reinvest(uint avaxRewards, uint amount) private {
        rewardController.claimReward(0, address(this));
        rewardController.claimReward(1, address(this));

        if (avaxRewards > 0) {
            WAVAX.deposit{value: avaxRewards}();
            DexLibrary.swap(avaxRewards, address(rewardToken1), address(rewardToken0), swapPairToken1);
        }

        uint devFee = amount.mul(DEV_FEE_BIPS).div(BIPS_DIVISOR);
        if (devFee > 0) {
            IERC20(address(rewardToken)).safeTransfer(devAddr, devFee);
        }

        uint adminFee = amount.mul(ADMIN_FEE_BIPS).div(BIPS_DIVISOR);
        if (adminFee > 0) {
            IERC20(address(rewardToken)).safeTransfer(owner(), adminFee);
        }

        uint reinvestFee = amount.mul(REINVEST_REWARD_BIPS).div(BIPS_DIVISOR);
        if (reinvestFee > 0) {
            IERC20(address(rewardToken)).safeTransfer(msg.sender, reinvestFee);
        }

        uint depositTokenAmount = amount.sub(devFee).sub(adminFee).sub(reinvestFee);

        _stakeDepositTokens(depositTokenAmount);

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
            require(tokenDelegator.mint(toBorrowAmount) == 0, "BenqiStrategyV1::lending failed");
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
            require(tokenDelegator.repayBorrow(unrollAmount) == 0, "BenqiStrategyV1::failed to repay borrow");
            balance = balance.sub(unrollAmount);
            borrowed = borrowed.sub(unrollAmount);
        }
    }

    function _stakeDepositTokens(uint amount) private {
        require(amount > 0, "BenqiStrategyV1::_stakeDepositTokens");
        require(tokenDelegator.mint(amount) == 0, "BenqiStrategyV1::Deposit failed");
        uint borrowed = tokenDelegator.borrowBalanceCurrent(address(this));
        uint principal = tokenDelegator.balanceOfUnderlying(address(this));
        _rollupDebt(principal, borrowed);
    }

    function _checkRewards() internal view returns (uint qiAmount, uint avaxAmount, uint totalQiAmount) {
        uint qiRewards = _getReward(0, address(this));
        uint avaxRewards = _getReward(1, address(this));

        uint wavaxAsQI = DexLibrary.estimateConversionThroughPair(
            avaxRewards, address(rewardToken1),
            address(rewardToken0), swapPairToken1
        );
        return (qiRewards, avaxRewards, qiRewards.add(wavaxAsQI));
    }

    function checkReward() public override view returns (uint) {
        (,,uint totalQiAmount) = _checkRewards();
        return totalQiAmount;
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

