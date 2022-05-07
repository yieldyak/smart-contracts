// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity 0.7.3;

import "../YakStrategyV2.sol";
import "../interfaces/IPair.sol";
import "../interfaces/IYakStrategy.sol";
import "../interfaces/RebasingToken.sol";
import "../interfaces/TimeStaking.sol";
import "../lib/DexLibrary.sol";

/**
 * This strategy is for LP that has a rebasing token. The strategy chases 
 * rebases when approaching an epoch and otherwise reuses existing LP farm.
 */
contract RebasingTokenStrategyForLP is YakStrategyV2 {
    using SafeMath for uint256;

    IWAVAX private constant WAVAX = IWAVAX(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);

    // Represent the state of PID.
    // 0 = YRT (unstaked); 1 = MEMO + WAVAX (staked)
    uint256 public PID;
    uint256 private constant UNSTAKED = 0;
    uint256 private constant STAKED = 1;

    address public yrt; // Yak farm for WAVAX-TIME LP
    address private poolRewardToken; // TIME
    address public stakingContract; // TIME <-> MEMO
    address public stakedToken; // MEMO
    uint256 private currentEpoch;
    uint256 private deposits; // track total deposits.

    struct StrategySettings {
        uint256 minTokensToReinvest;
        uint256 adminFeeBips;
        uint256 devFeeBips;
        uint256 reinvestRewardBips;
    }

    constructor(
        string memory _name,
        address _depositToken, // WAVAX-TIME LP
        address _ecosystemToken, // WAVAX
        address _poolRewardToken, // TIME
        address _stakingContract,
        address _timelock,
        uint256 _pid,
        StrategySettings memory _strategySettings
    ) Ownable() {
        name = _name;
        depositToken = IERC20(_depositToken);
        rewardToken = IERC20(_ecosystemToken);
        poolRewardToken = _poolRewardToken;
        PID = _pid;
        devAddr = 0x2D580F9CF2fB2D09BC411532988F2aFdA4E7BefF;
        stakingContract = _stakingContract;

        updateMinTokensToReinvest(_strategySettings.minTokensToReinvest);
        updateAdminFee(_strategySettings.adminFeeBips);
        updateDevFee(_strategySettings.devFeeBips);
        updateReinvestReward(_strategySettings.reinvestRewardBips);
        updateDepositsEnabled(true);
        transferOwnership(_timelock);
        emit Reinvest(0, 0);
    }

    /**
     * @notice Approve tokens for use in Strategy
     * @dev Deprecated; approvals should be handled in context of staking
     */
    function setAllowances() public override onlyOwner {
        revert("setAllowances::deprecated");
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
        require(DEPOSITS_ENABLED == true, "RebasingStrategyForLP::_deposit");
        if (MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST > 0) {
            _reinvest();
        }
        require(
            depositToken.transferFrom(msg.sender, address(this), amount),
            "RebasingStrategyForLP::transfer failed"
        );
        _mint(account, getSharesForDepositTokens(amount));
        _stakeDepositTokens(amount);
        deposits = deposits.add(amount);
        emit Deposit(account, amount);
    }

    function withdraw(uint256 amount) external override {
        uint256 depositTokenAmount = getDepositTokensForShares(amount);
        require(depositTokenAmount > 0, "RebasingStrategyForLP::withdraw");
        _withdrawDepositTokens(depositTokenAmount);
        _safeTransfer(address(depositToken), msg.sender, depositTokenAmount);
        _burn(msg.sender, amount);
        deposits = deposits.sub(depositTokenAmount);
        emit Withdraw(msg.sender, depositTokenAmount);
    }

    function _withdrawDepositTokens(uint256 amount) private {
        _withdrawMasterchef(PID, amount);
    }

    function reinvest() external override onlyEOA {
        require(_reinvest(), "RebasingStrategyForLP::reinvest");
    }

    // Reinvest if there are sufficient rewards.
    // Returns bool to indicate whether it happens.
    function _reinvest() internal returns (bool) {
        (
            uint256 rewardTokenAmount,
            uint256 poolTokenAmount,
            uint256 estimatedTotalReward
        ) = _checkReward();
        if (estimatedTotalReward < MIN_TOKENS_TO_REINVEST) {
            return false;
        }

        _getRewards(PID);
        uint256 amount = rewardTokenAmount.add(
            _convertPoolTokensIntoReward(poolTokenAmount)
        );
        uint256 devFee = amount.mul(DEV_FEE_BIPS).div(BIPS_DIVISOR);
        if (devFee > 0) {
            _safeTransfer(address(rewardToken), devAddr, devFee);
        }

        uint256 reinvestFee = amount.mul(REINVEST_REWARD_BIPS).div(BIPS_DIVISOR);
        if (reinvestFee > 0) {
            _safeTransfer(address(rewardToken), msg.sender, reinvestFee);
        }

        uint256 depositTokenAmount = _convertRewardTokenToDepositToken(
            amount.sub(devFee).sub(reinvestFee)
        );
        _stakeDepositTokens(depositTokenAmount);
        emit Reinvest(totalDeposits(), totalSupply);
        return true;
    }

    function _stakeDepositTokens(uint256 amount) private {
        require(amount > 0, "RebasingStrategyForLP::_stakeDepositTokens");
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
        require(
            IERC20(token).transfer(to, value),
            "RebasingStrategyForLP::TRANSFER_FROM_FAILED"
        );
    }

    function _checkReward()
        internal
        view
        returns (
            uint256 rewardTokenAmount,
            uint256 poolTokenAmount,
            uint256 estimatedTotalReward
        )
    {
        uint256 pendingRewards = _pendingRewards(PID, address(0));
        estimatedTotalReward = DexLibrary.estimateConversionThroughPair(
            poolTokenAmount,
            poolRewardToken,
            address(WAVAX),
            IPair(address(depositToken))
        );
        if (PID == STAKED) {
            rewardTokenAmount = 0;
            poolTokenAmount = pendingRewards;
        } else {
            rewardTokenAmount = estimatedTotalReward;
            poolTokenAmount = 0;
        }
    }

    function checkReward() public view override returns (uint256) {
        (, , uint256 estimatedTotalReward) = _checkReward();
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
        return deposits;
    }

    function rescueDeployedFunds(uint256 minReturnAmountAccepted, bool disableDeposits)
        external
        override
        onlyOwner
    {
        uint256 balanceBefore = depositToken.balanceOf(address(this));
        _emergencyWithdraw(PID);
        uint256 balanceAfter = depositToken.balanceOf(address(this));
        require(
            balanceAfter.sub(balanceBefore) >= minReturnAmountAccepted,
            "RebasingStrategyForLP::rescueDeployedFunds"
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
        DexLibrary.removeLiquidity(
            address(depositToken),
            liquidity,
            address(WAVAX),
            poolRewardToken
        );

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
        uint256 liquidity = DexLibrary.addLiquidity(
            address(depositToken),
            WAVAX.balanceOf(address(this)),
            unstakedBalance
        );
        require(liquidity > 0, "RebasingTokenStrategyForLP: no liquidity");

        // convert extra TIME to LP as well.
        uint256 leftoverLiquidity = DexLibrary.convertRewardTokensToDepositTokens(
            IERC20(poolRewardToken).balanceOf(address(this)),
            address(poolRewardToken),
            address(depositToken),
            IPair(address(depositToken)),
            IPair(address(depositToken))
        );
        require(leftoverLiquidity > 0, "RebasingTokenStrategyForLP: no liquidity");

        // 3. deposit liquidity to YY.
        IYakStrategy(yrt).deposit(liquidity.add(leftoverLiquidity));
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

    function _emergencyWithdraw(uint256 _pid) internal {
        if (_pid == STAKED) {
            _unstakeAll();
        }

        uint256 yrtBalance = IERC20(yrt).balanceOf(address(this));
        YakStrategyV2(yrt).withdraw(yrtBalance);
    }

    // Returns pending rewards in pool token (~0.6% TIME).
    // This reward is split to 20% for staking and 80% for unstaking.
    function _pendingRewards(uint256 _pid, address) internal view returns (uint256) {
        if (_pid == _getState()) {
            return 0;
        }

        (, uint256 stakingReward, , ) = TimeStaking(stakingContract).epoch();
        uint256 supply = RebasingToken(stakedToken).circulatingSupply();
        uint256 stakingRebasePercent = stakingReward.mul(100).div(supply);
        uint256 balance = IERC20(stakedToken).balanceOf(address(this));
        uint256 totalPendingRewards = balance.mul(stakingRebasePercent).div(100);
        if (_pid == UNSTAKED) {
            return totalPendingRewards.mul(20).div(100);
        } else {
            return totalPendingRewards.mul(80).div(100);
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

    function _convertPoolTokensIntoReward(uint256 poolTokenAmount)
        private
        returns (uint256)
    {
        return
            DexLibrary.swap(
                poolTokenAmount,
                address(poolRewardToken),
                address(rewardToken),
                IPair(address(depositToken))
            );
    }

    function _convertRewardTokenToDepositToken(uint256 fromAmount)
        internal
        returns (uint256 toAmount)
    {
        toAmount = DexLibrary.convertRewardTokensToDepositTokens(
            fromAmount,
            address(rewardToken),
            address(depositToken),
            IPair(address(depositToken)),
            IPair(address(depositToken))
        );
    }
}
