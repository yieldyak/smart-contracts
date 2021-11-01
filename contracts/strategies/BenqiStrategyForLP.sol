// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "../YakStrategy.sol";
import "../interfaces/IBenqiStakingContract.sol";
import "../interfaces/IPair.sol";
import "../lib/DexLibrary.sol";

/**
 * @notice Benqi strategy for staking QI-AVAX.
 */
contract BenqiStrategyForLP is YakStrategy {
    using SafeMath for uint256;

    IBenqiStakingContract private stakingContract;
    IERC20 private wavaxRewardToken;
    IERC20 private qiRewardToken;
    IPair private swapPairToken; // WAVAX-QI LP
    IWAVAX private constant WAVAX = IWAVAX(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);

    constructor(
        string memory _name,
        address _depositToken,
        address _qiRewardToken,
        address _stakingContract,
        address _swapPairToken,
        address _timelock,
        uint256 _minTokensToReinvest,
        uint256 _adminFeeBips,
        uint256 _devFeeBips,
        uint256 _reinvestRewardBips
    ) {
        name = _name;
        depositToken = IERC20(_depositToken);
        wavaxRewardToken = IERC20(address(WAVAX));
        rewardToken = wavaxRewardToken;
        qiRewardToken = IERC20(_qiRewardToken);
        stakingContract = IBenqiStakingContract(_stakingContract);
        devAddr = msg.sender;

        assignSwapPairSafely(_swapPairToken);
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
     * @notice Initialization helper for Pair deposit tokens
     * @dev Checks that selected Pairs are valid for trading deposit tokens
     * @dev Assigns values to swapPairToken0 and swapPairToken
     */
    function assignSwapPairSafely(address _swapPairToken) private {
        require(_swapPairToken > address(0), "Swap pair is necessary but not supplied");
        swapPairToken = IPair(_swapPairToken);
        require(
            isPairEquals(swapPairToken, wavaxRewardToken, qiRewardToken) ||
                isPairEquals(swapPairToken, qiRewardToken, wavaxRewardToken),
            "Swap pair does not match WAVAX or QI."
        );
    }

    function isPairEquals(
        IPair pair,
        IERC20 left,
        IERC20 right
    ) private returns (bool) {
        return pair.token0() == address(left) && pair.token1() == address(right);
    }

    function setAllowances() public override onlyOwner {
        depositToken.approve(address(stakingContract), MAX_UINT);
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
        require(DEPOSITS_ENABLED == true, "BenqiStrategyForLP::_deposit");
        if (MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST > 0) {
            (, uint256 qiAmount, uint256 totalAvaxAmount) = _checkRewards();
            if (totalAvaxAmount > MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST) {
                _reinvest(qiAmount);
            }
        }
        require(depositToken.transferFrom(account, address(this), amount));
        _stakeDepositTokens(amount);
        _mint(account, getSharesForDepositTokens(amount));
        totalDeposits = totalDeposits.add(amount);
        emit Deposit(account, amount);
    }

    function withdraw(uint256 amount) external override {
        uint256 depositTokenAmount = getDepositTokensForShares(amount);
        if (depositTokenAmount > 0) {
            _withdrawDepositTokens(depositTokenAmount);
            _safeTransfer(address(depositToken), msg.sender, depositTokenAmount);
            _burn(msg.sender, amount);
            totalDeposits = totalDeposits.sub(depositTokenAmount);
            emit Withdraw(msg.sender, depositTokenAmount);
        }
    }

    function _withdrawDepositTokens(uint256 amount) private {
        require(amount > 0, "BenqiStrategyForLP::_withdrawDepositTokens");
        stakingContract.redeem(amount);
    }

    // For Benqi to `recipient.transfer`. Keep this empty to reduce failures due to insufficient gas fee.
    receive() external payable {}

    function reinvest() external override onlyEOA {
        (, uint256 qiAmount, uint256 totalAvaxAmount) = _checkRewards();
        require(totalAvaxAmount >= MIN_TOKENS_TO_REINVEST, "BenqiStrategyForLP::reinvest");
        _reinvest(qiAmount);
    }

    /**
     * @notice Reinvest rewards from staking contract to deposit tokens
     * @dev Reverts if the expected amount of tokens are not returned from `stakingContract`
     * @param qiAmount amount of QI token to reinvest
     */
    function _reinvest(uint256 qiAmount) private {
        stakingContract.claimRewards();
        // wrap avax reward to wavax and check if avax reward has ended.
        // note: use balance to collect any left-over avax.
        uint256 avaxAmount = address(this).balance;
        if (avaxAmount > 0) {
            WAVAX.deposit{value: avaxAmount}();
        }

        require(qiAmount > 0, "BenqiStrategyForLP::_reinvest");
        uint256 qiAsWavax = DexLibrary.swap(qiAmount, address(qiRewardToken), address(wavaxRewardToken), swapPairToken);
        uint256 totalWavaxAmount = avaxAmount.add(qiAsWavax);
        uint256 amount = _reinvestToken(wavaxRewardToken, totalWavaxAmount);
        _stakeDepositTokens(amount);
        totalDeposits = totalDeposits.add(amount);
        emit Reinvest(totalDeposits, totalSupply);
    }

    function _reinvestToken(IERC20 token, uint256 amount) private returns (uint256 depositTokenAmount) {
        uint256 devFee = amount.mul(DEV_FEE_BIPS).div(BIPS_DIVISOR);
        if (devFee > 0) {
            _safeTransfer(address(token), devAddr, devFee);
        }

        uint256 adminFee = amount.mul(ADMIN_FEE_BIPS).div(BIPS_DIVISOR);
        if (adminFee > 0) {
            _safeTransfer(address(token), owner(), adminFee);
        }

        uint256 reinvestFee = amount.mul(REINVEST_REWARD_BIPS).div(BIPS_DIVISOR);
        if (reinvestFee > 0) {
            _safeTransfer(address(token), msg.sender, reinvestFee);
        }

        depositTokenAmount = DexLibrary.convertRewardTokensToDepositTokens(
            amount.sub(devFee).sub(adminFee).sub(reinvestFee),
            address(token),
            address(depositToken),
            swapPairToken,
            swapPairToken
        );
    }

    function _stakeDepositTokens(uint256 amount) private {
        require(amount > 0, "BenqiStrategyForLP::_stakeDepositTokens");
        stakingContract.deposit(amount);
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
        require(IERC20(token).transfer(to, value), "BenqiStrategyForLP::TRANSFER_FROM_FAILED");
    }

    function _checkRewards()
        internal
        view
        returns (
            uint256 avaxAmount,
            uint256 qiAmount,
            uint256 totalAvaxAmount
        )
    {
        avaxAmount = stakingContract.getClaimableRewards(0);
        qiAmount = stakingContract.getClaimableRewards(1);

        uint256 qiAsWavax = DexLibrary.estimateConversionThroughPair(
            qiAmount,
            address(qiRewardToken),
            address(wavaxRewardToken),
            swapPairToken
        );
        totalAvaxAmount = avaxAmount.add(qiAsWavax);
    }

    function checkReward() public view override returns (uint256) {
        (, , uint256 avaxRewards) = _checkRewards();
        return avaxRewards;
    }

    function estimateDeployedBalance() external view override returns (uint256) {
        return stakingContract.supplyAmount(address(this));
    }

    function rescueDeployedFunds(uint256 minReturnAmountAccepted, bool disableDeposits) external override onlyOwner {
        uint256 balanceBefore = stakingContract.supplyAmount(address(this));
        stakingContract.redeem(balanceBefore);
        uint256 balanceAfter = stakingContract.supplyAmount(address(this));
        require(balanceAfter.sub(balanceBefore) >= minReturnAmountAccepted, "BenqiStrategyForLP::rescueDeployedFunds");
        totalDeposits = balanceAfter;
        emit Reinvest(totalDeposits, totalSupply);
        if (DEPOSITS_ENABLED == true && disableDeposits == true) {
            updateDepositsEnabled(false);
        }
    }
}
