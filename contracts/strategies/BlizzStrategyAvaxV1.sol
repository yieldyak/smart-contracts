// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;
pragma experimental ABIEncoderV2;

import "../YakStrategyV2Payable.sol";
import "../interfaces/IBlizzChef.sol";
import "../interfaces/IBlizzMultiFeeDistribution.sol";
import "../interfaces/ILendingPool.sol";
import "../interfaces/IWAVAX.sol";
import "../interfaces/IERC20.sol";
import "../lib/SafeMath.sol";
import "../lib/DexLibrary.sol";
import "../lib/ReentrancyGuard.sol";

/**
 * @title Blizz strategy for AVAX
 * @dev No need to _enterMarket() as LendingPool already defaults collateral to true.
 * See https://github.com/aave/protocol-v2/blob/master/contracts/protocol/lendingpool/LendingPool.sol#L123-L126
 */
contract BlizzStrategyAvaxV1 is YakStrategyV2Payable, ReentrancyGuard {
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

    constructor(
        string memory _name,
        address _rewardDistribution,
        address _blizzChef,
        address _poolRewardToken,
        address _swapPairPoolReward,
        address _tokenDelegator,
        address _avToken,
        address _avDebtToken,
        address _timelock,
        LeverageSettings memory _leverageSettings,
        StrategySettings memory _strategySettings
    ) {
        name = _name;
        rewardDistribution = IBlizzMultiFeeDistribution(_rewardDistribution);
        blizzChef = IBlizzChef(_blizzChef);
        tokenDelegator = ILendingPool(_tokenDelegator);
        rewardToken = IERC20(address(WAVAX));
        poolRewardToken = _poolRewardToken;
        swapPairPoolReward = IPair(_swapPairPoolReward);
        _updateLeverage(_leverageSettings);
        devAddr = 0x2D580F9CF2fB2D09BC411532988F2aFdA4E7BefF;
        avToken = _avToken;
        avDebtToken = _avDebtToken;

        updateMinTokensToReinvest(_strategySettings.minTokensToReinvest);
        updateAdminFee(_strategySettings.adminFeeBips);
        updateDevFee(_strategySettings.devFeeBips);
        updateReinvestReward(_strategySettings.reinvestRewardBips);
        updateDepositsEnabled(true);
        transferOwnership(_timelock);

        emit Reinvest(0, 0);
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

    receive() external payable {
        require(msg.sender == address(WAVAX), "not allowed");
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
        emit Reinvest(totalDeposits(), totalSupply);
    }

    function setAllowances() public override onlyOwner {
        revert("Deprecated");
    }

    function _redeemUnderlying(uint256 amount) private returns (uint256) {
        IERC20(avToken).approve(address(tokenDelegator), amount);
        uint256 withdrawn = tokenDelegator.withdraw(address(WAVAX), amount, address(this));
        IERC20(avToken).approve(address(tokenDelegator), 0);
        return withdrawn;
    }

    function _repayBorrow(uint256 amount) private {
        WAVAX.approve(address(tokenDelegator), amount);
        tokenDelegator.repay(address(WAVAX), amount, 2, address(this));
        WAVAX.approve(address(tokenDelegator), 0);
    }

    function _depositCollateral(uint256 amount) private {
        WAVAX.approve(address(tokenDelegator), 0);
        tokenDelegator.deposit(address(WAVAX), amount, address(this), 0);
        WAVAX.approve(address(tokenDelegator), amount);
    }

    function deposit() external payable override nonReentrant {
        WAVAX.deposit{value: msg.value}();
        _deposit(msg.sender, msg.value);
    }

    function depositFor(address account) external payable override nonReentrant {
        WAVAX.deposit{value: msg.value}();
        _deposit(account, msg.value);
    }

    function deposit(uint256 amount) external override {
        revert();
    }

    function depositWithPermit(
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {
        revert();
    }

    function depositFor(address account, uint256 amount) external override {
        revert();
    }

    function _deposit(address account, uint256 amount) private onlyAllowedDeposits {
        require(DEPOSITS_ENABLED == true, "BlizzStrategyAvaxV1::_deposit");
        if (MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST > 0) {
            (uint256 poolTokenAmount, uint256 rewardTokenBalance, uint256 estimatedTotalReward) = _checkReward();
            if (estimatedTotalReward > MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST) {
                _reinvest(poolTokenAmount, rewardTokenBalance, estimatedTotalReward);
            }
        }
        _mint(account, getSharesForDepositTokens(amount));
        _stakeDepositTokens(amount);
        emit Deposit(account, amount);
    }

    function withdraw(uint256 amount) external override nonReentrant {
        uint256 WAVAXAmount = getDepositTokensForShares(amount);
        require(WAVAXAmount > minMinting, "BlizzStrategyAvaxV1::below minimum withdraw");
        _burn(msg.sender, amount);
        uint256 avaxAmount = _withdrawDepositTokens(WAVAXAmount);
        (bool success, ) = msg.sender.call{value: avaxAmount}("");
        require(success, "BlizzStrategyAvaxV1::transfer failed");
        emit Withdraw(msg.sender, avaxAmount);
    }

    function _withdrawDepositTokens(uint256 amount) private returns (uint256) {
        _unrollDebt(amount);
        (uint256 balance, , ) = _getAccountData();
        if (amount > balance) {
            // withdraws all
            amount = type(uint256).max;
        }
        uint256 withdrawn = _redeemUnderlying(amount);
        WAVAX.withdraw(withdrawn);
        _rollupDebt();
        return withdrawn;
    }

    function _convertPoolTokensIntoReward(uint256 poolTokenAmount) private returns (uint256) {
        return DexLibrary.swap(poolTokenAmount, address(poolRewardToken), address(rewardToken), swapPairPoolReward);
    }

    function reinvest() external override onlyEOA nonReentrant {
        (uint256 poolTokenAmount, uint256 rewardTokenBalance, uint256 estimatedTotalReward) = _checkReward();
        require(estimatedTotalReward >= MIN_TOKENS_TO_REINVEST, "BlizzStrategyAvaxV1::reinvest");
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

        _stakeDepositTokens(estimatedTotalReward.sub(devFee).sub(adminFee).sub(reinvestFee));

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
                address(WAVAX),
                borrowable,
                2, // variable interest model
                0,
                address(this)
            );
            _depositCollateral(borrowable);
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
            _redeemUnderlying(unrollAmount);
            _repayBorrow(unrollAmount);
            (balance, borrowed, borrowable) = _getAccountData();
            if (targetBorrow >= borrowed) {
                break;
            }
            toRepay = borrowed.sub(targetBorrow);
        }
    }

    function _stakeDepositTokens(uint256 amount) private {
        require(amount > 0, "BlizzStrategyAvaxV1::_stakeDepositTokens");
        _depositCollateral(amount);
        _rollupDebt();
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
        require(IERC20(token).transfer(to, value), "BlizzStrategyAvaxV1::TRANSFER_FROM_FAILED");
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
        uint256 balanceBefore = WAVAX.balanceOf(address(this));
        (uint256 balance, uint256 borrowed, ) = _getAccountData();
        _unrollDebt(balance.sub(borrowed));
        _redeemUnderlying(type(uint256).max);
        uint256 balanceAfter = WAVAX.balanceOf(address(this));
        require(balanceAfter.sub(balanceBefore) >= minReturnAmountAccepted, "BlizzStrategyAvaxV1::rescueDeployedFunds");
        IERC20(avToken).approve(address(tokenDelegator), 0);
        WAVAX.approve(address(tokenDelegator), 0);
        emit Reinvest(totalDeposits(), totalSupply);
        if (DEPOSITS_ENABLED == true && disableDeposits == true) {
            updateDepositsEnabled(false);
        }
    }
}
