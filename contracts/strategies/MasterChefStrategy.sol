// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "../YakStrategyV2.sol";

/**
 * @notice Adapter strategy for MasterChef.
 */
abstract contract MasterChefStrategy is YakStrategyV2 {
    using SafeMath for uint256;

    uint256 public immutable PID;
    address private stakingRewards;

    constructor(
        string memory _name,
        address _depositToken,
        address _rewardToken,
        address _stakingRewards,
        address _timelock,
        uint256 _pid,
        uint256 _minTokensToReinvest,
        uint256 _adminFeeBips,
        uint256 _devFeeBips,
        uint256 _reinvestRewardBips
    ) Ownable() {
        name = _name;
        depositToken = IERC20(_depositToken);
        rewardToken = IERC20(_rewardToken);
        PID = _pid;
        devAddr = msg.sender;
        stakingRewards = _stakingRewards;

        setAllowances();
        updateMinTokensToReinvest(_minTokensToReinvest);
        updateAdminFee(_adminFeeBips);
        updateDevFee(_devFeeBips);
        updateReinvestReward(_reinvestRewardBips);
        updateDepositsEnabled(true);
        transferOwnership(_timelock);
        emit Reinvest(0, 0);
    }

    /**
     * @notice Approve tokens for use in Strategy
     * @dev Restricted to avoid griefing attacks
     */
    function setAllowances() public override onlyOwner {
        depositToken.approve(stakingRewards, type(uint256).max);
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
            uint256 unclaimedRewards = checkReward();
            if (unclaimedRewards > MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST) {
                _reinvest(unclaimedRewards);
            }
        }
        require(depositToken.transferFrom(account, address(this), amount), "MasterChefStrategyV1::transfer failed");
        _stakeDepositTokens(amount);
        uint256 depositFeeBips = _getDepositFeeBips(PID);
        uint256 depositFee = amount.mul(depositFeeBips).div(_bip());
        _mint(account, getSharesForDepositTokens(amount.sub(depositFee)));
        emit Deposit(account, amount);
    }

    function withdraw(uint256 amount) external override {
        uint256 depositTokenAmount = getDepositTokensForShares(amount);
        if (depositTokenAmount > 0) {
            _withdrawDepositTokens(depositTokenAmount);
            uint256 withdrawFeeBips = _getWithdrawFeeBips(PID);
            uint256 withdrawFee = depositTokenAmount.mul(withdrawFeeBips).div(_bip());
            _safeTransfer(address(depositToken), msg.sender, depositTokenAmount.sub(withdrawFee));
            _burn(msg.sender, amount);
            emit Withdraw(msg.sender, depositTokenAmount);
        }
    }

    function _withdrawDepositTokens(uint256 amount) private {
        require(amount > 0, "MasterChefStrategyV1::_withdrawDepositTokens");
        _withdrawMasterchef(PID, amount);
    }

    function reinvest() external override onlyEOA {
        uint256 unclaimedRewards = checkReward();
        require(unclaimedRewards >= MIN_TOKENS_TO_REINVEST, "MasterChefStrategyV1::reinvest");
        _reinvest(unclaimedRewards);
    }

    /**
     * @notice Reinvest rewards from staking contract to deposit tokens
     * @dev Reverts if the expected amount of tokens are not returned from `MasterChef`
     * @param amount deposit tokens to reinvest
     */
    function _reinvest(uint256 amount) private {
        _getRewards(PID);

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

        uint256 depositTokenAmount = _convertRewardTokenToDepositToken(
            amount.sub(devFee).sub(adminFee).sub(reinvestFee)
        );
        _stakeDepositTokens(depositTokenAmount);
        emit Reinvest(totalDeposits(), totalSupply);
    }

    function _stakeDepositTokens(uint256 amount) private {
        require(amount > 0, "MasterChefStrategyV1::_stakeDepositTokens");
        _depositMasterchef(PID, amount);
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
        require(IERC20(token).transfer(to, value), "MasterChefStrategyV1::TRANSFER_FROM_FAILED");
    }

    function checkReward() public view override returns (uint256) {
        uint256 pendingReward = _pendingRewards(PID, address(this));
        uint256 contractBalance = rewardToken.balanceOf(address(this));
        return pendingReward.add(contractBalance);
    }

    /**
     * @notice Estimate recoverable balance after withdraw fee
     * @return deposit tokens after withdraw fee
     */
    function estimateDeployedBalance() external view override returns (uint256) {
        return _totalDeposits();
    }

    function totalDeposits() public view override returns (uint256) {
        return _totalDeposits();
    }

    function _totalDeposits() internal view returns (uint256) {
        uint256 depositBalance = _getDepositBalance(PID, address(this));
        uint256 withdrawFeeBips = _getWithdrawFeeBips(PID);
        uint256 withdrawFee = depositBalance.mul(withdrawFeeBips).div(_bip());
        return depositBalance.sub(withdrawFee);
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

    /* VIRTUAL */
    function _convertRewardTokenToDepositToken(uint256 fromAmount) internal virtual returns (uint256 toAmount);

    function _depositMasterchef(uint256 pid, uint256 amount) internal virtual;

    function _withdrawMasterchef(uint256 pid, uint256 amount) internal virtual;

    function _emergencyWithdraw(uint256 pid) internal virtual;

    function _getRewards(uint256 pid) internal virtual;

    function _pendingRewards(uint256 pid, address user) internal view virtual returns (uint256 amount);

    function _getDepositBalance(uint256 pid, address user) internal view virtual returns (uint256 amount);

    function _getDepositFeeBips(uint256 pid) internal view virtual returns (uint256);

    function _getWithdrawFeeBips(uint256 pid) internal view virtual returns (uint256);

    function _bip() internal view virtual returns (uint256);
}
