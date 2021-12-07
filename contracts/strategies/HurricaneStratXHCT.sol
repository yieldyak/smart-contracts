// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

import "../YakStrategy.sol";
import "../interfaces/IJoeBar.sol";
import "../interfaces/IHurricaneMasterChief.sol";
import "../interfaces/IPair.sol";

/**
 * @notice Single asset strategy for Hct
 */
contract CompoundingHct is YakStrategy {
    using SafeMath for uint256;

    IHurricaneMasterChief public stakingContract;
    IJoeBar public conversionContract;
    IERC20 public xHct;

    uint256 public PID;

    constructor(
        string memory _name,
        string memory _symbol,
        address _depositToken,
        address _rewardToken,
        address _stakingContract,
        address _conversionContract,
        address _timelock,
        uint256 _pid,
        uint256 _minTokensToReinvest,
        uint256 _adminFeeBips,
        uint256 _devFeeBips,
        uint256 _reinvestRewardBips
    ) {
        name = _name;
        symbol = _symbol;
        depositToken = IPair(_depositToken);
        rewardToken = IERC20(_rewardToken);
        stakingContract = IHurricaneMasterChief(_stakingContract);
        conversionContract = IJoeBar(_conversionContract);
        xHct = IERC20(_conversionContract);
        PID = _pid;
        devAddr = msg.sender;

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
        depositToken.approve(address(conversionContract), MAX_UINT);
        xHct.approve(address(stakingContract), MAX_UINT);
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

    /**
     * @notice Deposit Hct
     * @param account address
     * @param amount token amount
     */
    function _deposit(address account, uint256 amount) internal {
        require(DEPOSITS_ENABLED == true, "CompoundingHct::_deposit");
        if (MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST > 0) {
            uint256 unclaimedRewards = checkReward();
            if (unclaimedRewards > MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST) {
                _reinvest(unclaimedRewards);
            }
        }

        require(depositToken.transferFrom(msg.sender, address(this), amount));
        _stakeDepositTokens(amount);
        _mint(account, getSharesForDepositTokens(amount));
        totalDeposits = totalDeposits.add(amount);
        emit Deposit(account, amount);
    }

    function withdraw(uint256 amount) external override {
        uint256 depositTokenAmount = getDepositTokensForShares(amount);
        if (depositTokenAmount > 0) {
            _withdrawDepositTokens(depositTokenAmount);
            require(
                depositToken.transfer(msg.sender, depositTokenAmount),
                "CompoundingHct::withdraw"
            );
            _burn(msg.sender, amount);
            totalDeposits = totalDeposits.sub(depositTokenAmount);
            emit Withdraw(msg.sender, depositTokenAmount);
        }
    }

    /**
     * @notice Withdraw Hct
     * @param amount deposit tokens
     */
    function _withdrawDepositTokens(uint256 amount) private {
        require(amount > 0, "CompoundingHct::_withdrawDepositTokens");
        uint256 xHctAmount = _getxHctForHct(amount);
        stakingContract.withdraw(PID, xHctAmount);
        conversionContract.leave(xHctAmount);
    }

    function reinvest() external override onlyEOA {
        uint256 unclaimedRewards = checkReward();
        require(unclaimedRewards >= MIN_TOKENS_TO_REINVEST, "CompoundingHct::reinvest");
        _reinvest(unclaimedRewards);
    }

    /**
     * @notice Reinvest rewards from staking contract to deposit tokens
     * @dev Reverts if the expected amount of tokens are not returned from `stakingContract`
     * @param amount deposit tokens to reinvest
     */
    function _reinvest(uint256 amount) private {
        stakingContract.deposit(PID, 0);

        uint256 devFee = amount.mul(DEV_FEE_BIPS).div(BIPS_DIVISOR);
        if (devFee > 0) {
            require(
                rewardToken.transfer(devAddr, devFee),
                "CompoundingHct::_reinvest, dev"
            );
        }

        uint256 adminFee = amount.mul(ADMIN_FEE_BIPS).div(BIPS_DIVISOR);
        if (adminFee > 0) {
            require(
                rewardToken.transfer(owner(), adminFee),
                "CompoundingHct::_reinvest, admin"
            );
        }

        uint256 reinvestFee = amount.mul(REINVEST_REWARD_BIPS).div(BIPS_DIVISOR);
        if (reinvestFee > 0) {
            require(
                rewardToken.transfer(msg.sender, reinvestFee),
                "CompoundingHct::_reinvest, reward"
            );
        }

        uint256 depositTokenAmount = amount.sub(devFee).sub(adminFee).sub(reinvestFee);
        _stakeDepositTokens(depositTokenAmount);
        totalDeposits = totalDeposits.add(depositTokenAmount);

        emit Reinvest(totalDeposits, totalSupply);
    }

    /**
     * @notice Convert and stake Hct
     * @param amount deposit tokens
     */
    function _stakeDepositTokens(uint256 amount) private {
        uint256 xHctAmount = _getxHctForHct(amount);
        _convertHctToxHct(amount);
        _stakexHct(xHctAmount);
    }

    /**
     * @notice Convert Hct to xHct
     * @param amount deposit token
     */
    function _convertHctToxHct(uint256 amount) private {
        require(amount > 0, "CompoundingHct::_convertHctToxHct");
        conversionContract.enter(amount);
    }

    /**
     * @notice Stake xHct
     * @param amount xHct
     */
    function _stakexHct(uint256 amount) private {
        require(amount > 0, "CompoundingHct::_stakexHct");
        stakingContract.deposit(PID, amount);
    }

    function checkReward() public view override returns (uint256) {
        (uint256 pendingReward, ) = stakingContract.pending(PID, address(this));
        uint256 contractBalance = rewardToken.balanceOf(address(this));
        return pendingReward.add(contractBalance);
    }

    /**
     * @notice Estimate recoverable balance
     * @return deposit tokens
     */
    function estimateDeployedBalance() external view override returns (uint256) {
        (uint256 depositBalance, , ) = stakingContract.userInfo(PID, address(this));
        return _getHctForxHct(depositBalance);
    }

    /**
     * @notice Conversion rate for Hct to xHct
     * @param amount Hct tokens
     * @return xHct shares
     */
    function _getxHctForHct(uint256 amount) private view returns (uint256) {
        uint256 HctBalance = depositToken.balanceOf(address(conversionContract));
        uint256 xHctShares = xHct.totalSupply();
        if (HctBalance.mul(xHctShares) == 0) {
            return amount;
        }
        return amount.mul(xHctShares).div(HctBalance);
    }

    /**
     * @notice Conversion rate for xHct to Hct
     * @param amount xHct shares
     * @return Hct tokens
     */
    function _getHctForxHct(uint256 amount) private view returns (uint256) {
        uint256 HctBalance = depositToken.balanceOf(address(conversionContract));
        uint256 xHctShares = xHct.totalSupply();
        if (HctBalance.mul(xHctShares) == 0) {
            return amount;
        }
        return amount.mul(HctBalance).div(xHctShares);
    }

    function emergencyWithdraw() external onlyOwner {
        stakingContract.emergencyWithdraw(PID);
        totalDeposits = 0;
    }

    function rescueDeployedFunds(uint256 minReturnAmountAccepted, bool disableDeposits)
        external
        override
        onlyOwner
    {
        uint256 balanceBefore = depositToken.balanceOf(address(this));
        stakingContract.emergencyWithdraw(PID);
        conversionContract.leave(xHct.balanceOf(address(this)));
        uint256 balanceAfter = depositToken.balanceOf(address(this));
        require(
            balanceAfter.sub(balanceBefore) >= minReturnAmountAccepted,
            "CompoundingHct::rescueDeployedFunds"
        );
        totalDeposits = balanceAfter;
        emit Reinvest(totalDeposits, totalSupply);
        if (DEPOSITS_ENABLED == true && disableDeposits == true) {
            updateDepositsEnabled(false);
        }
    }
}
