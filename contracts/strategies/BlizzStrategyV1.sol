// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "../YakStrategyV2.sol";
import "../interfaces/IBlizzChef.sol";
import "../interfaces/IBlizzMultiFeeDistribution.sol";
import "../interfaces/ILendingPool.sol";
import "../interfaces/IWAVAX.sol";
import "../interfaces/IERC20.sol";
import "../lib/SafeMath.sol";
import "../lib/DexLibrary.sol";
import "../lib/ReentrancyGuard.sol";

/**
 * @title Blizz strategy for ERC20
 */
contract BlizzStrategyV1 is YakStrategyV2 {
    using SafeMath for uint256;

    struct StrategySettings {
        uint256 minTokensToReinvest;
        uint256 adminFeeBips;
        uint256 devFeeBips;
        uint256 reinvestRewardBips;
    }

    struct LeverageSettings {
        uint256 leverageLevel;
        uint256 safetyFactor;
        uint256 leverageBips;
        uint256 minMinting;
    }

    struct SwapPairs {
        address swapPairRewardDeposit;
        address swapPairPoolReward;
    }

    struct Tokens {
        address depositToken;
        address poolRewardToken;
        address avToken;
        address avDebtToken;
    }

    IBlizzMultiFeeDistribution private rewardDistribution;
    IBlizzChef private blizzChef;
    ILendingPool private tokenDelegator;
    IWAVAX private constant WAVAX = IWAVAX(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);
    uint256 private leverageLevel;
    uint256 private safetyFactor;
    uint256 private leverageBips;
    uint256 private minMinting;
    address private avToken;
    address private avDebtToken;
    address private poolRewardToken;
    IPair private swapPairPoolReward;
    IPair private swapPairRewardDeposit;

    constructor(
        string memory _name,
        address _rewardDistribution,
        address _blizzChef,
        address _tokenDelegator,
        address _timelock,
        Tokens memory _tokens,
        SwapPairs memory _swapPairs,
        LeverageSettings memory _leverageSettings,
        StrategySettings memory _strategySettings
    ) {
        name = _name;
        rewardDistribution = IBlizzMultiFeeDistribution(_rewardDistribution);
        blizzChef = IBlizzChef(_blizzChef);
        tokenDelegator = ILendingPool(_tokenDelegator);
        depositToken = IERC20(_tokens.depositToken);
        rewardToken = IERC20(address(WAVAX));
        poolRewardToken = _tokens.poolRewardToken;
        swapPairPoolReward = IPair(_swapPairs.swapPairPoolReward);
        _updateLeverage(_leverageSettings);
        devAddr = msg.sender;
        avToken = _tokens.avToken;
        avDebtToken = _tokens.avDebtToken;

        assignSwapPairSafely(_swapPairs.swapPairRewardDeposit);
        setAllowances();
        updateMinTokensToReinvest(_strategySettings.minTokensToReinvest);
        updateAdminFee(_strategySettings.adminFeeBips);
        updateDevFee(_strategySettings.devFeeBips);
        updateReinvestReward(_strategySettings.reinvestRewardBips);
        updateDepositsEnabled(true);
        transferOwnership(_timelock);

        emit Reinvest(0, 0);
    }

    function assignSwapPairSafely(address _swapPairRewardDeposit) private {
        require(_swapPairRewardDeposit > address(0), "Swap pair is necessary but not supplied");
        swapPairRewardDeposit = IPair(_swapPairRewardDeposit);
        require(
            isPairEquals(swapPairRewardDeposit, depositToken, rewardToken) ||
                isPairEquals(swapPairRewardDeposit, rewardToken, depositToken),
            "Swap pair does not match depositToken and rewardToken."
        );
    }

    function isPairEquals(
        IPair pair,
        IERC20 left,
        IERC20 right
    ) private pure returns (bool) {
        return pair.token0() == address(left) && pair.token1() == address(right);
    }

    /// @notice Internal method to get account state
    /// @dev Values provided in 1e18 (WAD) instead of 1e27 (RAY)
    function _getAccountData()
        internal
        view
        returns (
            uint256 balance,
            uint256 borrowed,
            uint256 borrowable
        )
    {
        balance = IERC20(avToken).balanceOf(address(this));
        borrowed = IERC20(avDebtToken).balanceOf(address(this));
        borrowable = 0;
        if (balance.mul(leverageLevel.sub(leverageBips)).div(leverageLevel) > borrowed) {
            borrowable = balance.mul(leverageLevel.sub(leverageBips)).div(leverageLevel).sub(borrowed);
        }
    }

    function totalDeposits() public view override returns (uint256) {
        (uint256 balance, uint256 borrowed, ) = _getAccountData();
        return balance.sub(borrowed);
    }

    function _updateLeverage(LeverageSettings memory _leverageSettings) internal {
        leverageLevel = _leverageSettings.leverageLevel;
        leverageBips = _leverageSettings.leverageBips;
        safetyFactor = _leverageSettings.safetyFactor;
        minMinting = _leverageSettings.minMinting;
    }

    function updateLeverage(
        uint256 _leverageLevel,
        uint256 _safetyFactor,
        uint256 _minMinting,
        uint256 _leverageBips
    ) external onlyDev {
        _updateLeverage(
            LeverageSettings({
                leverageLevel: _leverageLevel,
                safetyFactor: _safetyFactor,
                minMinting: _minMinting,
                leverageBips: _leverageBips
            })
        );
        (uint256 balance, uint256 borrowed, ) = _getAccountData();
        _unrollDebt(balance.sub(borrowed));
        _rollupDebt();
    }

    function setAllowances() public override onlyOwner {
        IERC20(depositToken).approve(address(tokenDelegator), type(uint256).max);
        IERC20(avToken).approve(address(tokenDelegator), type(uint256).max);
    }

    function deposit(uint256 amount) external override {
        _deposit(msg.sender, amount);
    }

    function depositFor(address account, uint256 amount) external override {
        _deposit(account, amount);
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

    function _deposit(address account, uint256 amount) private onlyAllowedDeposits {
        require(DEPOSITS_ENABLED == true, "BlizzStrategyV1::_deposit");
        if (MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST > 0) {
            (uint256 poolTokenAmount, uint256 rewardTokenBalance, uint256 estimatedTotalReward) = _checkReward();
            if (estimatedTotalReward > MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST) {
                _reinvest(poolTokenAmount, rewardTokenBalance, estimatedTotalReward);
            }
        }
        require(depositToken.transferFrom(msg.sender, address(this), amount), "BlizzStrategyV1::transfer failed");
        _mint(account, getSharesForDepositTokens(amount));
        _stakeDepositTokens(amount);
        emit Deposit(account, amount);
    }

    function withdraw(uint256 amount) external override {
        uint256 depositTokenAmount = getDepositTokensForShares(amount);
        require(depositTokenAmount > minMinting, "BlizzStrategyV1::below minimum withdraw");
        if (depositTokenAmount > 0) {
            _burn(msg.sender, amount);
            // actual amount withdrawn may change with time.
            uint256 withdrawnAmount = _withdrawDepositTokens(depositTokenAmount);
            _safeTransfer(address(depositToken), msg.sender, withdrawnAmount);
            emit Withdraw(msg.sender, withdrawnAmount);
        }
    }

    function _withdrawDepositTokens(uint256 amount) private returns (uint256) {
        _unrollDebt(amount);
        (uint256 balance, , ) = _getAccountData();
        amount = amount > balance ? type(uint256).max : amount;
        uint256 withdrawn = tokenDelegator.withdraw(address(depositToken), amount, address(this));
        _rollupDebt();
        return withdrawn;
    }

    function _convertPoolTokensIntoReward(uint256 poolTokenAmount) private returns (uint256) {
        return DexLibrary.swap(poolTokenAmount, address(poolRewardToken), address(rewardToken), swapPairPoolReward);
    }

    function reinvest() external override onlyEOA {
        (uint256 poolTokenAmount, uint256 rewardTokenBalance, uint256 estimatedTotalReward) = _checkReward();
        require(estimatedTotalReward >= MIN_TOKENS_TO_REINVEST, "BlizzStrategyV1::reinvest");
        _reinvest(poolTokenAmount, rewardTokenBalance, estimatedTotalReward);
    }

    /**
     * @notice Reinvest rewards from staking contract to deposit tokens
     * @dev Reverts if the expected amount of tokens are not returned from `stakingContract`
     */
    function _reinvest(
        uint256 poolTokenAmount,
        uint256 rewardTokenBalance,
        uint256 estimatedTotalReward
    ) private {
        address[] memory assets = new address[](2);
        assets[0] = avToken;
        assets[1] = avDebtToken;
        blizzChef.claim(address(this), assets);
        rewardDistribution.exit(true);

        _convertPoolTokensIntoReward(poolTokenAmount);

        uint256 devFee = estimatedTotalReward.mul(DEV_FEE_BIPS).div(BIPS_DIVISOR);
        if (devFee > 0) {
            _safeTransfer(address(rewardToken), devAddr, devFee);
        }

        uint256 adminFee = estimatedTotalReward.mul(ADMIN_FEE_BIPS).div(BIPS_DIVISOR);
        if (adminFee > 0) {
            _safeTransfer(address(rewardToken), owner(), adminFee);
        }

        uint256 reinvestFee = estimatedTotalReward.mul(REINVEST_REWARD_BIPS).div(BIPS_DIVISOR);
        if (reinvestFee > 0) {
            _safeTransfer(address(rewardToken), msg.sender, reinvestFee);
        }

        uint256 depositTokenAmount = DexLibrary.swap(
            estimatedTotalReward.sub(devFee).sub(adminFee).sub(reinvestFee),
            address(rewardToken),
            address(depositToken),
            swapPairRewardDeposit
        );
        _stakeDepositTokens(depositTokenAmount);

        emit Reinvest(totalDeposits(), totalSupply);
    }

    function _rollupDebt() internal {
        (uint256 balance, uint256 borrowed, uint256 borrowable) = _getAccountData();
        uint256 lendTarget = balance.sub(borrowed).mul(leverageLevel.sub(safetyFactor)).div(leverageBips);
        while (balance < lendTarget) {
            if (balance.add(borrowable) > lendTarget) {
                borrowable = lendTarget.sub(balance);
            }
            if (borrowable < minMinting) {
                break;
            }
            tokenDelegator.borrow(
                address(depositToken),
                borrowable,
                2, // variable interest model
                0,
                address(this)
            );
            tokenDelegator.deposit(address(depositToken), borrowable, address(this), 0);
            (balance, borrowed, borrowable) = _getAccountData();
        }
    }

    function _unrollDebt(uint256 amountToFreeUp) internal {
        (uint256 balance, uint256 borrowed, uint256 borrowable) = _getAccountData();
        uint256 targetBorrow = balance
            .sub(borrowed)
            .sub(amountToFreeUp)
            .mul(leverageLevel.sub(safetyFactor))
            .div(leverageBips)
            .sub(balance.sub(borrowed).sub(amountToFreeUp));
        uint256 toRepay = borrowed.sub(targetBorrow);

        while (toRepay > 0) {
            uint256 unrollAmount = borrowable;
            if (unrollAmount > borrowed) {
                unrollAmount = borrowed;
            }
            tokenDelegator.withdraw(address(depositToken), unrollAmount, address(this));
            tokenDelegator.repay(address(depositToken), unrollAmount, 2, address(this));
            (balance, borrowed, borrowable) = _getAccountData();
            if (targetBorrow >= borrowed) {
                break;
            }
            toRepay = borrowed.sub(targetBorrow);
        }
    }

    function _stakeDepositTokens(uint256 amount) private {
        require(amount > 0, "BlizzStrategyV1::_stakeDepositTokens");
        tokenDelegator.deposit(address(depositToken), amount, address(this), 0);
        _rollupDebt();
    }

    /**
     * @notice Safely transfer using an anonymosu ERC20 token
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
        require(IERC20(token).transfer(to, value), "BlizzStrategyV1::TRANSFER_FROM_FAILED");
    }

    function _updatePool(IBlizzChef.PoolInfo memory pool) internal view returns (IBlizzChef.PoolInfo memory) {
        if (block.timestamp <= pool.lastRewardTime) {
            return pool;
        }
        uint256 lpSupply = pool.totalSupply;
        if (lpSupply == 0) {
            pool.lastRewardTime = block.timestamp;
            return pool;
        }
        uint256 duration = block.timestamp.sub(pool.lastRewardTime);
        uint256 reward = duration.mul(blizzChef.rewardsPerSecond()).mul(pool.allocPoint).div(
            blizzChef.totalAllocPoint()
        );
        pool.accRewardPerShare = pool.accRewardPerShare.add(reward.mul(1e12).div(lpSupply));
        return pool;
    }

    function _checkReward()
        internal
        view
        returns (
            uint256 _poolTokenAmount,
            uint256 _rewardTokenBalance,
            uint256 _estimatedTotalReward
        )
    {
        uint256 poolTokenAmount = blizzChef.userBaseClaimable(address(this));

        address[] memory assets = new address[](2);
        assets[0] = avToken;
        assets[1] = avDebtToken;

        IBlizzChef.PoolInfo memory pool = blizzChef.poolInfo(assets[0]);
        pool = _updatePool(pool);
        IBlizzChef.UserInfo memory user = blizzChef.userInfo(assets[0], address(this));
        uint256 rewardDebt = user.amount.mul(pool.accRewardPerShare).div(1e12);
        poolTokenAmount = poolTokenAmount.add(rewardDebt.sub(user.rewardDebt));

        pool = blizzChef.poolInfo(assets[1]);
        pool = _updatePool(pool);
        user = blizzChef.userInfo(assets[1], address(this));
        rewardDebt = user.amount.mul(pool.accRewardPerShare).div(1e12);
        poolTokenAmount = poolTokenAmount.add(rewardDebt.sub(user.rewardDebt));

        poolTokenAmount = poolTokenAmount.div(2);
        poolTokenAmount = poolTokenAmount.add(IERC20(poolRewardToken).balanceOf(address(this)));
        uint256 pendingRewardTokenAmount = DexLibrary.estimateConversionThroughPair(
            poolTokenAmount,
            poolRewardToken,
            address(rewardToken),
            swapPairPoolReward
        );
        uint256 rewardTokenBalance = rewardToken.balanceOf(address(this));
        uint256 estimatedTotalReward = pendingRewardTokenAmount.add(rewardTokenBalance);
        return (poolTokenAmount, rewardTokenBalance, estimatedTotalReward);
    }

    function checkReward() public view override returns (uint256) {
        (, , uint256 amount) = _checkReward();
        return amount;
    }

    function getActualLeverage() public view returns (uint256) {
        (uint256 balance, uint256 borrowed, ) = _getAccountData();
        return balance.mul(1e18).div(balance.sub(borrowed));
    }

    function estimateDeployedBalance() external view override returns (uint256) {
        return totalDeposits();
    }

    function rescueDeployedFunds(uint256 minReturnAmountAccepted, bool disableDeposits) external override onlyOwner {
        uint256 balanceBefore = depositToken.balanceOf(address(this));
        (uint256 balance, uint256 borrowed, ) = _getAccountData();
        _unrollDebt(balance.sub(borrowed));
        tokenDelegator.withdraw(address(depositToken), type(uint256).max, address(this));
        uint256 balanceAfter = depositToken.balanceOf(address(this));
        require(balanceAfter.sub(balanceBefore) >= minReturnAmountAccepted, "BlizzStrategyV1::rescueDeployedFunds");
        emit Reinvest(totalDeposits(), totalSupply);
        if (DEPOSITS_ENABLED == true && disableDeposits == true) {
            updateDepositsEnabled(false);
        }
    }
}
