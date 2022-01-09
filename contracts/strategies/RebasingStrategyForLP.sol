// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity 0.7.3;

import "../YakStrategyV2.sol";
import "../interfaces/IPair.sol";
import "../interfaces/IYakStrategy.sol";
import "../interfaces/TimeStaking.sol";
import "../lib/DexLibrary.sol";

/**
 * Deposit token = WAVAX-TIME LP
 * Reward token = WAVAX
 * Native reward token = TIME
 * "MasterChef"
 *   PID 0 = unstaked (YRT)
 *   PID 1 = staked (MEMO+WAVAX)
 * Staking contract = YRT farm
 * Additional staking contract = TimeStaking.
 *
 * Deposit is a little more complicated as it needs to reconcile the PID and the upcoming state.
 * For example, if PID is currently 0 and current epoch is ending soon, then we stake the deposit and underlying asset.
 *
 * On deposit:
 * 1. if current epoch is closing soon, flip PID to 1 and handle accordingly;
 * 2. else, flip PID to 1 and do a simple deposit.
Basically, deposit checks if current epoch closing soon, then flip to PID 0; else simple deposit.

Reinvest only has balance when before epoch ends and after epoch starts. Proposal: 0.01% WAVAX for before. Then once we get 0.06% TIME, swap to WAVAX and minus the 0.01% to calculate remaining.
 */
contract RebasingTokenStrategyForLP is YakStrategyV2 {
    using SafeMath for uint256;

    IWAVAX private constant WAVAX = IWAVAX(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);

    // Represent the state of PID.
    // 0 = YRT (unstaked); 1 = MEMO + WAVAX (staked)
    uint256 private UNSTAKED = 0;
    uint256 private STAKED = 1;

    address public yrt; // Yak farm for WAVAX-TIME LP
    address public stakingContract; // TIME <-> MEMO
    address public swapPairRewardToken;
    address public stakedToken; // MEMO
    uint256 private currentEpoch;

    // address _depositToken, // WAVAX-TIME LP
    // address _rewardToken, // WAVAX
    // address _nativeRewardToken, // TIME

    struct StrategySettings {
        uint256 minTokensToReinvest;
        uint256 adminFeeBips;
        uint256 devFeeBips;
        uint256 reinvestRewardBips;
    }

    uint256 public PID;
    address private poolRewardToken;
    IPair private swapPairPoolReward;
    address public swapPairExtraReward;
    address public extraToken;

    constructor(
        string memory _name,
        address _depositToken,
        address _ecosystemToken,
        address _poolRewardToken,
        address _swapPairPoolReward,
        address _swapPairExtraReward,
        address _stakingContract,
        address _timelock,
        uint256 _pid,
        StrategySettings memory _strategySettings
    ) Ownable() {
        name = _name;
        depositToken = IERC20(_depositToken);
        rewardToken = IERC20(_ecosystemToken);
        PID = _pid;
        devAddr = 0x2D580F9CF2fB2D09BC411532988F2aFdA4E7BefF;
        stakingContract = _stakingContract;

        assignSwapPairSafely(_ecosystemToken, _poolRewardToken, _swapPairPoolReward);
        _setExtraRewardSwapPair(_swapPairExtraReward);
        updateMinTokensToReinvest(_strategySettings.minTokensToReinvest);
        updateAdminFee(_strategySettings.adminFeeBips);
        updateDevFee(_strategySettings.devFeeBips);
        updateReinvestReward(_strategySettings.reinvestRewardBips);
        updateDepositsEnabled(true);
        transferOwnership(_timelock);
        emit Reinvest(0, 0);
    }

    /**
     * @notice Initialization helper for Pair deposit tokens
     * @dev Checks that selected Pairs are valid for trading reward tokens
     * @dev Assigns values to IPair(swapPairToken0) and IPair(swapPairToken1)
     */
    function assignSwapPairSafely(
        address _ecosystemToken,
        address _poolRewardToken,
        address _swapPairPoolReward
    ) private {
        if (_poolRewardToken != _ecosystemToken) {
            if (_poolRewardToken == IPair(_swapPairPoolReward).token0()) {
                require(
                    IPair(_swapPairPoolReward).token1() == _ecosystemToken,
                    "Swap pair 'swapPairPoolReward' does not contain ecosystem token"
                );
            } else if (_poolRewardToken == IPair(_swapPairPoolReward).token1()) {
                require(
                    IPair(_swapPairPoolReward).token0() == _ecosystemToken,
                    "Swap pair 'swapPairPoolReward' does not contain ecosystem token"
                );
            } else {
                revert("Swap pair 'swapPairPoolReward' does not contain pool reward token");
            }
        }
        poolRewardToken = _poolRewardToken;
        swapPairPoolReward = IPair(_swapPairPoolReward);
    }

    /**
     * @notice Approve tokens for use in Strategy
     * @dev Deprecated; approvals should be handled in context of staking
     */
    function setAllowances() public override onlyOwner {
        revert("setAllowances::deprecated");
    }

    function setExtraRewardSwapPair(address _extraTokenSwapPair) external onlyDev {
        _setExtraRewardSwapPair(_extraTokenSwapPair);
    }

    function _setExtraRewardSwapPair(address _extraTokenSwapPair) internal {
        if (_extraTokenSwapPair > address(0)) {
            if (IPair(_extraTokenSwapPair).token0() == address(rewardToken)) {
                extraToken = IPair(_extraTokenSwapPair).token1();
            } else {
                extraToken = IPair(_extraTokenSwapPair).token0();
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
        require(DEPOSITS_ENABLED == true, "MasterChefStrategyV1::_deposit");
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
        }
        require(depositToken.transferFrom(msg.sender, address(this), amount), "MasterChefStrategyV1::transfer failed");
        _mint(account, getSharesForDepositTokens(amount));
        _stakeDepositTokens(amount);
        emit Deposit(account, amount);
    }

    function withdraw(uint256 amount) external override {
        uint256 depositTokenAmount = getDepositTokensForShares(amount);
        require(depositTokenAmount > 0, "MasterChefStrategyV1::withdraw");
        _withdrawDepositTokens(depositTokenAmount);
        _safeTransfer(address(depositToken), msg.sender, depositTokenAmount);
        _burn(msg.sender, amount);
        emit Withdraw(msg.sender, depositTokenAmount);
    }

    function _withdrawDepositTokens(uint256 amount) private {
        _withdrawMasterchef(PID, amount);
    }

    function reinvest() external override onlyEOA {
        (
            uint256 poolTokenAmount,
            uint256 extraTokenAmount,
            uint256 rewardTokenBalance,
            uint256 estimatedTotalReward
        ) = _checkReward();
        require(estimatedTotalReward >= MIN_TOKENS_TO_REINVEST, "MasterChefStrategyV1::reinvest");
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
        _getRewards(PID);
        uint256 amount = rewardTokenBalance.add(_convertPoolTokensIntoReward(poolTokenAmount));
        amount.add(_convertExtraTokensIntoReward(rewardTokenBalance, extraTokenAmount));

        uint256 devFee = amount.mul(DEV_FEE_BIPS).div(BIPS_DIVISOR);
        if (devFee > 0) {
            _safeTransfer(address(rewardToken), devAddr, devFee);
        }

        uint256 reinvestFee = amount.mul(REINVEST_REWARD_BIPS).div(BIPS_DIVISOR);
        if (reinvestFee > 0) {
            _safeTransfer(address(rewardToken), msg.sender, reinvestFee);
        }

        uint256 depositTokenAmount = _convertRewardTokenToDepositToken(amount.sub(devFee).sub(reinvestFee));

        _stakeDepositTokens(depositTokenAmount);
        emit Reinvest(totalDeposits(), totalSupply);
    }

    function _stakeDepositTokens(uint256 amount) private {
        require(amount > 0, "MasterChefStrategyV1::_stakeDepositTokens");
        _depositMasterchef(PID, amount);
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
        require(IERC20(token).transfer(to, value), "MasterChefStrategyV1::TRANSFER_FROM_FAILED");
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
            PID,
            address(this)
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

    function checkReward() public view override returns (uint256) {
        (, , , uint256 estimatedTotalReward) = _checkReward();
        return estimatedTotalReward;
    }

    /**
     * @notice Estimate recoverable balance after withdraw fee
     * @return deposit tokens after withdraw fee
     */
    function estimateDeployedBalance() external view override returns (uint256) {
        return totalDeposits();
    }

    function totalDeposits() public view override returns (uint256) {
        uint256 depositBalance = _getDepositBalance(PID, address(this));
        return depositBalance;
    }

    function rescueDeployedFunds(uint256 minReturnAmountAccepted, bool disableDeposits) external override onlyOwner {
        uint256 balanceBefore = depositToken.balanceOf(address(this));
        _emergencyWithdraw(PID);
        uint256 balanceAfter = depositToken.balanceOf(address(this));
        require(
            balanceAfter.sub(balanceBefore) >= minReturnAmountAccepted,
            "MasterChefStrategyV1::rescueDeployedFunds"
        );
        emit Reinvest(totalDeposits(), totalSupply);
        if (DEPOSITS_ENABLED == true && disableDeposits == true) {
            updateDepositsEnabled(false);
        }
    }

    // An epoch is ending with there is less than a minute left.
    // Note: do not call _stakeAll and then _unstakeAll, since first call will update the epoch.
    function _isEpochEnding() internal view returns (bool) {
        // check epoch to guard against clock skew.
        (uint256 epochNumber, , , uint32 endTime) = TimeStaking(stakingContract).epoch();
        return epochNumber == currentEpoch && endTime <= block.timestamp + 60;
    }

    // Return current state (PID). 0 = unstaked; PID 1 = staked.
    function _getState() internal view returns (uint256) {
        return _isEpochEnding() ? STAKED : UNSTAKED;
    }

    // case (_pid, currentState)
    // (unstaked, unstaked) = simple deposit
    // (unstaked, staked) = simple deposit, stake all
    // (staked, unstaked) = unstake all, simple deposit
    // (staked, staked) = simple deposit, stake all
    function _depositMasterchef(uint256 _pid, uint256 _amount) internal {
        require(
            depositToken.transferFrom(msg.sender, address(this), _amount),
            "RebasingTokenStrategyForLP: insufficient balance"
        );
        PID = _getState();

        if (_pid == STAKED && PID == UNSTAKED) {
            _unstakeAll();
        }

        IYakStrategy(yrt).deposit(_amount);

        if (PID == STAKED) {
            _stakeAll();
        }
    }

    // Stake all TIME to MEMO
    function _stakeAll() internal {
        require(_isEpochEnding(), "RebasingTokenStrategyForLP: too late to stake");
        currentEpoch = currentEpoch + 1;

        // 1. withdraw liquidity from YY.
        uint256 yrtBalance = IERC20(yrt).balanceOf(address(this));
        YakStrategyV2(yrt).withdraw(yrtBalance);

        // 2. remove liquidity WAVAX-TIME.
        uint256 liquidity = IPair(address(depositToken)).balanceOf(address(this));
        require(liquidity > 0, "RebasingTokenStrategyForLP: no liquidity");
        // TODO: implement this
        // (uint256 wavaxAmount, uint256 timeAmount) = DexLibrary.removeLiquidity(...);

        // 3. stake TIME to MEMO.
        uint256 poolRewardTokenBalance = IERC20(poolRewardToken).balanceOf(
            address(this)
        );
        require(
            poolRewardTokenBalance > 0,
            "RebasingTokenStrategyForLP: no token to stake"
        );
        TimeStaking(stakingContract).stake(poolRewardTokenBalance, address(this));
        TimeStaking(stakingContract).claim(address(this));
    }

    // Unstake all MEMO to TIME
    function _unstakeAll() internal {
        require(!_isEpochEnding(), "RebasingTokenStrategyForLP: too early to unstake");
        // 1. unstake MEMO to TIME.
        uint256 stakedBalance = IERC20(stakedToken).balanceOf(address(this));
        if (stakedBalance > 0) {
            TimeStaking(stakingContract).unstake(stakedBalance, true);
        }
        uint256 unstakedBalance = IERC20(poolRewardToken).balanceOf(address(this));
        require(unstakedBalance > 0, "RebasingTokenStrategyForLP: no unstaked");

        // 2. add liquidity WAVAX-TIME.
        // FIXME: zap the extra TIME to liquidity too.
        uint256 liquidity = DexLibrary.addLiquidity(
            address(depositToken),
            WAVAX.balanceOf(address(this)),
            unstakedBalance
        );
        require(liquidity > 0, "RebasingTokenStrategyForLP: no liquidity");

        // 3. deposit liquidity to YY.
        IYakStrategy(yrt).deposit(liquidity);
    }

    // case (_pid, currentState)
    // (unstaked, unstaked) = simple withdraw
    // (unstaked, staked) = simple withdraw, stake all
    // (staked, unstaked) = unstake all, simple withdraw
    // (staked, staked) = unstake all, simple withdraw, stake all
    // Potential optimization: only unstake just enough.
    function _withdrawMasterchef(uint256 _pid, uint256 _amount) internal {
        PID = _getState();
        if (_pid == STAKED) {
            _unstakeAll();
        }

        IYakStrategy(yrt).withdraw(_amount);
        require(
            depositToken.transfer(msg.sender, _amount),
            "RebasingTokenStrategyForLP: unable to withdraw"
        );

        if (PID == STAKED) {
            _stakeAll();
        }
    }

    function _emergencyWithdraw(uint256 _pid) internal {}

    // Total reward is about 0.6% TIME. Allocate 20% to unstaking and 80% to staking.
    function _pendingRewards(uint256 _pid, address)
        internal
        view
        returns (
            uint256,
            uint256,
            address
        )
    {
        // FIXME:
        // _checkReward returns the sum of rewardToken (WAVAX) and poolToken (TIME) balance and pending poolToken.
        // When UNSTAKED, we have no rewardToken and poolToken balance.
        // When STAKED, we have 50% rewardToken balance and 0 poolToken balance.
        if (_pid == UNSTAKED) {
            // look at our LP. estimate 
            return (123, 0, address(0));
        } else {
            return (123, 0, address(0));
        }

    }

    function _getRewards(uint256 _pid) internal {
        PID = _getState();
        require(_pid != PID, "RebasingTokenStrategyForLP: no rewards");
        if (PID == UNSTAKED) {
            _unstakeAll();
        } else {
            _stakeAll();
        }
    }

    function _convertRewardTokenToDepositToken(uint256 fromAmount) internal returns (uint256 toAmount) {
        //dex library swap
    }

    function _getDepositBalance(uint256 pid, address user)
        internal
        view
        returns (uint256 amount)
    {}
}
