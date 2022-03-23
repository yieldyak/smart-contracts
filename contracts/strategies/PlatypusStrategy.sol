// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity 0.7.3;

import "../interfaces/IMasterPlatypus.sol";
import "../interfaces/IPlatypusPool.sol";
import "../interfaces/IPlatypusVoterProxy.sol";
import "../interfaces/IPlatypusAsset.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IPair.sol";
import "../interfaces/IWAVAX.sol";
import "../lib/DexLibrary.sol";
import "../lib/SafeERC20.sol";
import "../lib/DSMath.sol";
import "../YakStrategyV2.sol";

contract PlatypusStrategy is YakStrategyV2 {
    using SafeMath for uint256;
    using DSMath for uint256;
    using SafeERC20 for IERC20;

    struct SwapPairs {
        address swapPairToken; // swap rewardToken to depositToken
        address swapPairPoolReward;
        address swapPairExtraReward;
    }

    struct StrategySettings {
        uint256 minTokensToReinvest;
        uint256 adminFeeBips;
        uint256 devFeeBips;
        uint256 reinvestRewardBips;
    }

    IWAVAX private constant WAVAX = IWAVAX(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);
    uint256 internal constant WAD = 10**18;
    uint256 internal constant RAY = 10**27;

    IMasterPlatypus public immutable masterchef;
    IPlatypusAsset public immutable asset;
    IPlatypusPool public pool;
    IPlatypusVoterProxy public proxy;
    uint256 public maxSlippage;
    address private swapPairToken;
    uint256 public immutable PID;
    address private poolRewardToken;
    IPair private swapPairPoolReward;
    address public swapPairExtraReward;
    address public extraToken;

    constructor(
        string memory _name,
        address _depositToken,
        address _poolRewardToken,
        SwapPairs memory swapPairs,
        uint256 _maxSlippage,
        address _pool,
        address _stakingContract,
        address _voterProxy,
        uint256 _pid,
        address _timelock,
        StrategySettings memory _strategySettings
    ) {
        name = _name;
        depositToken = IERC20(_depositToken);
        rewardToken = IERC20(address(WAVAX));
        PID = _pid;
        devAddr = 0x2D580F9CF2fB2D09BC411532988F2aFdA4E7BefF;

        masterchef = IMasterPlatypus(_stakingContract);
        pool = IPlatypusPool(_pool);
        asset = IPlatypusAsset(pool.assetOf(_depositToken));
        proxy = IPlatypusVoterProxy(_voterProxy);
        maxSlippage = _maxSlippage;

        assignSwapPairSafely(swapPairs.swapPairToken, _poolRewardToken, swapPairs.swapPairPoolReward);
        _setExtraRewardSwapPair(swapPairs.swapPairExtraReward);
        updateMinTokensToReinvest(_strategySettings.minTokensToReinvest);
        updateAdminFee(_strategySettings.adminFeeBips);
        updateDevFee(_strategySettings.devFeeBips);
        updateReinvestReward(_strategySettings.reinvestRewardBips);
        updateDepositsEnabled(true);
        transferOwnership(_timelock);
        emit Reinvest(0, 0);
    }

    function setPlatypusVoterProxy(address _voterProxy) external onlyOwner {
        proxy = IPlatypusVoterProxy(_voterProxy);
    }

    /**
     * @notice Update max slippage for withdrawal
     * @dev Function name matches interface for FeeCollector
     */
    function updateMaxSwapSlippage(uint256 slippageBips) public onlyDev {
        maxSlippage = slippageBips;
    }

    /**
     * @notice Approve tokens for use in Strategy
     * @dev Deprecated; approvals should be handled in context of staking
     */
    function setAllowances() public override onlyOwner {
        revert("setAllowances::deprecated");
    }

    /**
     * @notice Update extra reward swap pair (if applicable)
     * @dev Function name matches interface for FeeCollector
     */
    function setExtraRewardSwapPair(address _extraTokenSwapPair) external onlyDev {
        _setExtraRewardSwapPair(_extraTokenSwapPair);
    }

    function assignSwapPairSafely(
        address _swapPairToken,
        address _poolRewardToken,
        address _swapPairPoolReward
    ) private {
        require(
            DexLibrary.checkSwapPairCompatibility(IPair(_swapPairToken), address(depositToken), address(rewardToken)),
            "swap token does not match deposit and reward token"
        );
        swapPairToken = _swapPairToken;

        if (_poolRewardToken != address(rewardToken)) {
            DexLibrary.checkSwapPairCompatibility(IPair(_swapPairPoolReward), address(rewardToken), _poolRewardToken);
        }
        poolRewardToken = _poolRewardToken;
        swapPairPoolReward = IPair(_swapPairPoolReward);
    }

    function _setExtraRewardSwapPair(address _extraTokenSwapPair) internal {
        if (_extraTokenSwapPair > address(0)) {
            if (IPair(_extraTokenSwapPair).token0() == address(rewardToken)) {
                extraToken = IPair(_extraTokenSwapPair).token1();
            } else if (IPair(_extraTokenSwapPair).token1() == address(rewardToken)) {
                extraToken = IPair(_extraTokenSwapPair).token0();
            } else {
                revert("PlatypusStrategy::_setExtraRewardSwapPair Swap pair does not contain reward token");
            }
            swapPairExtraReward = _extraTokenSwapPair;
        } else {
            swapPairExtraReward = address(0);
            extraToken = address(0);
        }
    }

    /**
     * @notice Deposit tokens to receive receipt tokens
     * @param amount Amount of tokens to deposit
     */
    function deposit(uint256 amount) external override {
        _deposit(msg.sender, amount);
    }

    /**
     * @notice Deposit using Permit
     * @param amount Amount of tokens to deposit
     * @param deadline The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
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

    function _deposit(address account, uint256 amount) internal {
        require(DEPOSITS_ENABLED == true, "PlatypusStrategy::_deposit");
        if (MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST > 0) {
            (
                uint256 poolTokenAmount,
                uint256 extraTokenAmount,
                uint256 rewardTokenBalance,
                uint256 estimatedTotalReward
            ) = _checkReward();
            if (estimatedTotalReward > MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST) {
                _reinvest(rewardTokenBalance, poolTokenAmount, extraTokenAmount);
            }
        } else {
            proxy.claimReward(address(masterchef), PID);
        }
        depositToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 depositFee = _calculateDepositFee(amount);
        _mint(account, getSharesForDepositTokens(amount.sub(depositFee)));
        _stakeDepositTokens(amount, depositFee);
        emit Deposit(account, amount.sub(depositFee));
    }

    function _depositMasterchef(
        uint256 _pid,
        uint256 _amount,
        uint256 _depositFee
    ) internal {
        depositToken.safeTransfer(address(proxy), _amount);
        proxy.deposit(
            _pid,
            address(masterchef),
            address(pool),
            address(depositToken),
            address(asset),
            _amount,
            _depositFee
        );
    }

    function withdraw(uint256 amount) external override {
        uint256 depositTokenAmount = getDepositTokensForShares(amount);
        require(depositTokenAmount > 0, "PlatypusStrategy::withdraw");
        proxy.claimReward(address(masterchef), PID);
        uint256 withdrawalAmount = proxy.withdraw(
            PID,
            address(masterchef),
            address(pool),
            address(depositToken),
            address(asset),
            maxSlippage,
            depositTokenAmount
        );
        depositToken.safeTransfer(msg.sender, withdrawalAmount);
        _burn(msg.sender, amount);
        emit Withdraw(msg.sender, depositTokenAmount);
    }

    function reinvest() external override onlyEOA {
        (
            uint256 poolTokenAmount,
            uint256 extraTokenAmount,
            uint256 rewardTokenBalance,
            uint256 estimatedTotalReward
        ) = _checkReward();
        require(estimatedTotalReward >= MIN_TOKENS_TO_REINVEST, "PlatypusStrategy::reinvest");
        _reinvest(rewardTokenBalance, poolTokenAmount, extraTokenAmount);
    }

    function _convertPoolTokensIntoReward(uint256 poolTokenAmount) private returns (uint256) {
        if (address(rewardToken) == poolRewardToken) {
            return poolTokenAmount;
        }
        return DexLibrary.swap(poolTokenAmount, address(poolRewardToken), address(rewardToken), swapPairPoolReward);
    }

    function _convertExtraTokensIntoReward(uint256 rewardTokenBalance, uint256 extraTokenAmount)
        internal
        returns (uint256)
    {
        if (extraTokenAmount > 0) {
            if (swapPairExtraReward > address(0)) {
                return DexLibrary.swap(extraTokenAmount, extraToken, address(rewardToken), IPair(swapPairExtraReward));
            }

            uint256 avaxBalance = address(this).balance;
            if (avaxBalance > 0) {
                WAVAX.deposit{value: avaxBalance}();
            }
            return WAVAX.balanceOf(address(this)).sub(rewardTokenBalance);
        }
        return 0;
    }

    /**
     * @notice Reinvest rewards from staking contract to deposit tokens
     * @dev Reverts if the expected amount of tokens are not returned from `MasterChef`
     */
    function _reinvest(
        uint256 rewardTokenBalance,
        uint256 poolTokenAmount,
        uint256 extraTokenAmount
    ) private {
        proxy.claimReward(address(masterchef), PID);
        uint256 amount = rewardTokenBalance.add(_convertPoolTokensIntoReward(poolTokenAmount));
        amount.add(_convertExtraTokensIntoReward(rewardTokenBalance, extraTokenAmount));

        uint256 devFee = amount.mul(DEV_FEE_BIPS).div(BIPS_DIVISOR);
        if (devFee > 0) {
            rewardToken.safeTransfer(devAddr, devFee);
        }

        uint256 reinvestFee = amount.mul(REINVEST_REWARD_BIPS).div(BIPS_DIVISOR);
        if (reinvestFee > 0) {
            rewardToken.safeTransfer(msg.sender, reinvestFee);
        }

        uint256 depositTokenAmount = _convertRewardTokenToDepositToken(amount.sub(devFee).sub(reinvestFee));

        uint256 depositFee = _calculateDepositFee(depositTokenAmount);
        _stakeDepositTokens(depositTokenAmount, depositFee);

        emit Reinvest(totalDeposits(), totalSupply);
    }

    function _convertRewardTokenToDepositToken(uint256 fromAmount) internal returns (uint256 toAmount) {
        toAmount = DexLibrary.swap(fromAmount, address(rewardToken), address(depositToken), IPair(swapPairToken));
    }

    function _stakeDepositTokens(uint256 amount, uint256 depositFee) private {
        require(amount.sub(depositFee) > 0, "PlatypusStrategy::_stakeDepositTokens");
        _depositMasterchef(PID, amount, depositFee);
    }

    function checkReward() public view override returns (uint256) {
        (, , , uint256 estimatedTotalReward) = _checkReward();
        return estimatedTotalReward;
    }

    function _checkReward()
        internal
        view
        returns (
            uint256 _poolTokenAmount,
            uint256 _extraTokenAmount,
            uint256 _rewardTokenBalance,
            uint256 _estimatedTotalReward
        )
    {
        uint256 poolTokenBalance = IERC20(poolRewardToken).balanceOf(address(this));
        (uint256 pendingPoolTokenAmount, uint256 pendingExtraTokenAmount, address extraTokenAddress) = _pendingRewards(
            PID
        );
        uint256 poolTokenAmount = poolTokenBalance.add(pendingPoolTokenAmount);

        uint256 pendingRewardTokenAmount = poolRewardToken != address(rewardToken)
            ? DexLibrary.estimateConversionThroughPair(
                poolTokenAmount,
                poolRewardToken,
                address(rewardToken),
                swapPairPoolReward
            )
            : pendingPoolTokenAmount;
        uint256 pendingExtraTokenRewardAmount = 0;
        if (extraTokenAddress > address(0)) {
            if (extraTokenAddress == address(WAVAX)) {
                pendingExtraTokenRewardAmount = pendingExtraTokenAmount;
            } else if (swapPairExtraReward > address(0)) {
                pendingExtraTokenAmount = pendingExtraTokenAmount.add(IERC20(extraToken).balanceOf(address(this)));
                pendingExtraTokenRewardAmount = DexLibrary.estimateConversionThroughPair(
                    pendingExtraTokenAmount,
                    extraTokenAddress,
                    address(rewardToken),
                    IPair(swapPairExtraReward)
                );
            }
        }
        uint256 rewardTokenBalance = rewardToken.balanceOf(address(this)).add(pendingExtraTokenRewardAmount);
        uint256 estimatedTotalReward = rewardTokenBalance.add(pendingRewardTokenAmount);
        return (poolTokenAmount, pendingExtraTokenAmount, rewardTokenBalance, estimatedTotalReward);
    }

    function _pendingRewards(uint256 _pid)
        internal
        view
        returns (
            uint256,
            uint256,
            address
        )
    {
        (uint256 pendingPtp, uint256 pendingBonusToken, address bonusTokenAddress) = proxy.pendingRewards(
            address(masterchef),
            _pid
        );
        uint256 reinvestFeeBips = proxy.reinvestFeeBips();
        uint256 boostFee = pendingPtp.mul(reinvestFeeBips).div(BIPS_DIVISOR);

        return (pendingPtp.sub(boostFee), pendingBonusToken, bonusTokenAddress);
    }

    function _calculateDepositFee(uint256 amount) internal view returns (uint256 fee) {
        return
            _depositFee(
                pool.getSlippageParamK(),
                pool.getSlippageParamN(),
                pool.getC1(),
                pool.getXThreshold(),
                asset.cash(),
                asset.liability(),
                amount
            );
    }

    function _depositFee(
        uint256 k,
        uint256 n,
        uint256 c1,
        uint256 xThreshold,
        uint256 cash,
        uint256 liability,
        uint256 amount
    ) internal pure returns (uint256) {
        // cover case where the asset has no liquidity yet
        if (liability == 0) {
            return 0;
        }

        uint256 covBefore = cash.wdiv(liability);
        if (covBefore <= 10**18) {
            return 0;
        }

        uint256 covAfter = (cash.add(amount)).wdiv(liability.add(amount));
        uint256 slippageBefore = _slippageFunc(k, n, c1, xThreshold, covBefore);
        uint256 slippageAfter = _slippageFunc(k, n, c1, xThreshold, covAfter);

        // (Li + Di) * g(cov_after) - Li * g(cov_before)
        return ((liability.add(amount)).wmul(slippageAfter)) - (liability.wmul(slippageBefore));
    }

    function _slippageFunc(
        uint256 k,
        uint256 n,
        uint256 c1,
        uint256 xThreshold,
        uint256 x
    ) internal pure returns (uint256) {
        if (x < xThreshold) {
            return c1.sub(x);
        } else {
            return k.wdiv((((x.mul(RAY)).div(WAD)).rpow(n).mul(WAD)).div(RAY)); // k / (x ** n)
        }
    }

    /**
     * @notice Estimate recoverable balance after withdraw fee
     * @return deposit tokens after withdraw fee
     */
    function estimateDeployedBalance() external view override returns (uint256) {
        uint256 balance = totalDeposits();
        if (balance == 0) {
            return 0;
        }
        (uint256 expectedAmount, , ) = pool.quotePotentialWithdraw(address(depositToken), balance);
        return expectedAmount;
    }

    function totalDeposits() public view override returns (uint256) {
        uint256 depositBalance = proxy.poolBalance(address(masterchef), PID);
        return depositBalance;
    }

    function rescueDeployedFunds(uint256 minReturnAmountAccepted, bool disableDeposits) external override onlyOwner {
        uint256 balanceBefore = depositToken.balanceOf(address(this));
        proxy.emergencyWithdraw(PID, address(masterchef), address(pool), address(depositToken), address(asset));
        uint256 balanceAfter = depositToken.balanceOf(address(this));
        require(balanceAfter.sub(balanceBefore) >= minReturnAmountAccepted, "PlatypusStrategy::rescueDeployedFunds");
        emit Reinvest(totalDeposits(), totalSupply);
        if (DEPOSITS_ENABLED == true && disableDeposits == true) {
            updateDepositsEnabled(false);
        }
    }
}
