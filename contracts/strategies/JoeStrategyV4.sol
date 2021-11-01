// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "../YakStrategy.sol";
import "../interfaces/IJoeChef.sol";
import "../interfaces/IPair.sol";
import "../interfaces/IWAVAX.sol";
import "../interfaces/IERC20.sol";
import "../lib/DexLibrary.sol";

/**
 * @notice Strategy for Trader Joe, which includes optional and variable extra rewards
 * @dev Fees are paid in WAVAX
 */
contract JoeStrategyV4 is YakStrategy {
    using SafeMath for uint256;

    IJoeChef public stakingContract;
    IPair private swapPairWAVAXJoe;
    IPair private swapPairExtraToken;
    IPair private swapPairToken0;
    IPair private swapPairToken1;
    IERC20 private poolRewardToken;
    uint256 private PID;
    IWAVAX private constant WAVAX = IWAVAX(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);
    bytes private constant zeroBytes = new bytes(0);

    constructor(
        string memory _name,
        address _depositToken,
        address _poolRewardToken,
        address _rewardToken,
        address _stakingContract,
        address _swapPairWAVAXJoe,
        address _swapPairToken0,
        address _swapPairToken1,
        address _extraTokenSwapPair,
        uint256 pid,
        address _timelock,
        uint256 _minTokensToReinvest,
        uint256 _adminFeeBips,
        uint256 _devFeeBips,
        uint256 _reinvestRewardBips
    ) {
        name = _name;
        depositToken = IERC20(_depositToken);
        rewardToken = IERC20(_rewardToken);
        poolRewardToken = IERC20(_poolRewardToken);
        stakingContract = IJoeChef(_stakingContract);
        devAddr = msg.sender;
        PID = pid;

        assignSwapPairSafely(_swapPairWAVAXJoe, _extraTokenSwapPair, _swapPairToken0, _swapPairToken1);
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
     * @dev Checks that selected Pairs are valid for trading reward tokens
     * @dev Assigns values to swapPairToken0 and swapPairToken1
     */
    function assignSwapPairSafely(
        address _swapPairWAVAXJoe,
        address _extraTokenSwapPair,
        address _swapPairToken0,
        address _swapPairToken1
    ) private {
        require(
            DexLibrary.checkSwapPairCompatibility(IPair(_swapPairWAVAXJoe), address(WAVAX), address(poolRewardToken)),
            "_swapPairWAVAXJoe is not a WAVAX-Joe pair"
        );
        require(
            _swapPairToken0 == address(0) ||
                DexLibrary.checkSwapPairCompatibility(
                    IPair(_swapPairToken0),
                    address(WAVAX),
                    IPair(address(depositToken)).token0()
                ),
            "_swapPairToken0 is not a WAVAX+deposit token0"
        );
        require(
            _swapPairToken1 == address(0) ||
                DexLibrary.checkSwapPairCompatibility(
                    IPair(_swapPairToken1),
                    address(WAVAX),
                    IPair(address(depositToken)).token1()
                ),
            "_swapPairToken1 is not a WAVAX+deposit token1"
        );
        (, address extraRewardToken, , ) = stakingContract.pendingTokens(PID, address(this));
        require(
            _extraTokenSwapPair == address(0) ||
                DexLibrary.checkSwapPairCompatibility(IPair(_extraTokenSwapPair), address(WAVAX), extraRewardToken),
            "_swapPairWAVAXJoe is not a WAVAX-extra reward pair, check stakingContract.pendingTokens"
        );
        // converts Joe to WAVAX
        swapPairWAVAXJoe = IPair(_swapPairWAVAXJoe);
        // converts extra reward to WAVAX
        swapPairExtraToken = IPair(_extraTokenSwapPair);
        // converts WAVAX to pair token0
        swapPairToken0 = IPair(_swapPairToken0);
        // converts WAVAX to pair token1
        swapPairToken1 = IPair(_swapPairToken1);
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

    receive() external payable {
        (, , , , address rewarder) = stakingContract.poolInfo(PID);
        require(
            msg.sender == rewarder ||
                msg.sender == address(stakingContract) ||
                msg.sender == owner() ||
                msg.sender == address(devAddr),
            "not allowed"
        );
    }

    function _deposit(address account, uint256 amount) private onlyAllowedDeposits {
        require(DEPOSITS_ENABLED == true, "JoeStrategyV4::_deposit");
        if (MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST > 0) {
            uint256 unclaimedRewards = checkReward();
            if (unclaimedRewards > MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST) {
                (
                    uint256 poolTokenAmount,
                    address extraRewardTokenAddress,
                    uint256 extraRewardTokenAmount,
                    uint256 rewardTokenAmount
                ) = _checkReward();
                _reinvest(poolTokenAmount, extraRewardTokenAddress, extraRewardTokenAmount, rewardTokenAmount);
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
            _safeTransfer(address(depositToken), msg.sender, depositTokenAmount);
            _burn(msg.sender, amount);
            totalDeposits = totalDeposits.sub(depositTokenAmount);
            emit Withdraw(msg.sender, depositTokenAmount);
        }
    }

    function _withdrawDepositTokens(uint256 amount) private {
        require(amount > 0, "JoeStrategyV4::_withdrawDepositTokens");
        stakingContract.withdraw(PID, amount);
    }

    function reinvest() external override onlyEOA {
        uint256 unclaimedRewards = checkReward();
        require(unclaimedRewards >= MIN_TOKENS_TO_REINVEST, "JoeStrategyV4::reinvest");
        (
            uint256 poolTokenAmount,
            address extraRewardTokenAddress,
            uint256 extraRewardTokenAmount,
            uint256 rewardTokenAmount
        ) = _checkReward();
        _reinvest(poolTokenAmount, extraRewardTokenAddress, extraRewardTokenAmount, rewardTokenAmount);
    }

    function _convertRewardIntoWAVAX(
        uint256 pendingJoe,
        address extraRewardToken,
        uint256 pendingExtraReward
    ) private returns (uint256) {
        uint256 convertedAmountWAVAX = 0;

        if (extraRewardToken == address(WAVAX)) {
            uint256 avaxBalance = address(this).balance;
            if (avaxBalance > 0) {
                WAVAX.deposit{value: avaxBalance}();
            }
            convertedAmountWAVAX = convertedAmountWAVAX.add(WAVAX.balanceOf(address(this)));
        } else if (extraRewardToken == address(poolRewardToken)) {
            convertedAmountWAVAX = convertedAmountWAVAX.add(
                DexLibrary.swap(
                    pendingExtraReward.add(pendingJoe),
                    address(poolRewardToken),
                    address(WAVAX),
                    swapPairWAVAXJoe
                )
            );
            return convertedAmountWAVAX;
        }

        convertedAmountWAVAX = convertedAmountWAVAX.add(
            DexLibrary.swap(pendingJoe, address(poolRewardToken), address(WAVAX), swapPairWAVAXJoe)
        );
        if (
            address(swapPairExtraToken) != address(0) &&
            pendingExtraReward > 0 &&
            DexLibrary.checkSwapPairCompatibility(swapPairExtraToken, extraRewardToken, address(WAVAX))
        ) {
            convertedAmountWAVAX = convertedAmountWAVAX.add(
                DexLibrary.swap(pendingExtraReward, extraRewardToken, address(WAVAX), swapPairExtraToken)
            );
        }
        return convertedAmountWAVAX;
    }

    /**
     * @notice Reinvest rewards from staking contract to deposit tokens
     * @dev Reverts if the expected amount of tokens are not returned from `stakingContract`
     */
    function _reinvest(
        uint256 _pendingJoe,
        address _extraRewardToken,
        uint256 _pendingExtraToken,
        uint256 _pendingWavax
    ) private {
        stakingContract.deposit(PID, 0);
        uint256 amount = _pendingWavax.add(_convertRewardIntoWAVAX(_pendingJoe, _extraRewardToken, _pendingExtraToken));

        uint256 devFee = amount.mul(DEV_FEE_BIPS).div(BIPS_DIVISOR);
        if (devFee > 0) {
            _safeTransfer(address(WAVAX), devAddr, devFee);
        }

        uint256 adminFee = amount.mul(ADMIN_FEE_BIPS).div(BIPS_DIVISOR);
        if (adminFee > 0) {
            _safeTransfer(address(WAVAX), owner(), adminFee);
        }

        uint256 reinvestFee = amount.mul(REINVEST_REWARD_BIPS).div(BIPS_DIVISOR);
        if (reinvestFee > 0) {
            _safeTransfer(address(WAVAX), msg.sender, reinvestFee);
        }

        uint256 depositTokenAmount = DexLibrary.convertRewardTokensToDepositTokens(
            amount.sub(devFee).sub(adminFee).sub(reinvestFee),
            address(WAVAX),
            address(depositToken),
            swapPairToken0,
            swapPairToken1
        );

        _stakeDepositTokens(depositTokenAmount);
        totalDeposits = totalDeposits.add(depositTokenAmount);

        emit Reinvest(totalDeposits, totalSupply);
    }

    function _stakeDepositTokens(uint256 amount) private {
        require(amount > 0, "JoeStrategyV4::_stakeDepositTokens");
        stakingContract.deposit(PID, amount);
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
        require(IERC20(token).transfer(to, value), "TransferHelper: TRANSFER_FROM_FAILED");
    }

    function setExtraRewardSwapPair(address swapPair) external onlyDev {
        if (swapPair == address(0)) {
            swapPairExtraToken = IPair(address(0));
            return;
        }

        (, address extraRewardToken, , ) = stakingContract.pendingTokens(PID, address(this));
        require(
            DexLibrary.checkSwapPairCompatibility(IPair(swapPair), address(WAVAX), extraRewardToken),
            "_swapPairWAVAXJoe is not a WAVAX-extra reward pair, check stakingContract.pendingTokens"
        );
        swapPairExtraToken = IPair(swapPair);
    }

    function _checkReward()
        private
        view
        returns (
            uint256 poolTokenAmount,
            address extraRewardTokenAddress,
            uint256 extraRewardTokenAmount,
            uint256 rewardTokenAmount
        )
    {
        (uint256 pendingJoe, address extraRewardToken, , uint256 pendingExtraToken) = stakingContract.pendingTokens(
            PID,
            address(this)
        );
        uint256 poolRewardBalance = poolRewardToken.balanceOf(address(this));
        uint256 extraRewardTokenBalance;
        if (extraRewardToken != address(0)) {
            extraRewardTokenBalance = IERC20(extraRewardToken).balanceOf(address(this));
        }
        uint256 rewardTokenBalance = rewardToken.balanceOf(address(this));
        return (
            poolRewardBalance.add(pendingJoe),
            extraRewardToken,
            extraRewardTokenBalance.add(pendingExtraToken),
            rewardTokenBalance
        );
    }

    function checkReward() public view override returns (uint256) {
        (
            uint256 poolTokenAmount,
            address extraRewardTokenAddress,
            uint256 extraRewardTokenAmount,
            uint256 rewardTokenAmount
        ) = _checkReward();
        uint256 estimatedWAVAX = DexLibrary.estimateConversionThroughPair(
            poolTokenAmount,
            address(poolRewardToken),
            address(WAVAX),
            swapPairWAVAXJoe
        );
        if (
            address(swapPairExtraToken) != address(0) &&
            extraRewardTokenAmount > 0 &&
            DexLibrary.checkSwapPairCompatibility(swapPairExtraToken, extraRewardTokenAddress, address(WAVAX))
        ) {
            estimatedWAVAX.add(
                DexLibrary.estimateConversionThroughPair(
                    extraRewardTokenAmount,
                    extraRewardTokenAddress,
                    address(WAVAX),
                    swapPairExtraToken
                )
            );
        }
        return rewardTokenAmount.add(estimatedWAVAX);
    }

    function estimateDeployedBalance() external view override returns (uint256) {
        (uint256 amount, ) = stakingContract.userInfo(PID, address(this));
        return amount;
    }

    /**
     * @notice Allows exit from Staking Contract without additional logic
     * @dev Reward tokens are not automatically collected
     * @dev New deposits will be effectively disabled
     */
    function emergencyWithdraw() external onlyOwner {
        stakingContract.emergencyWithdraw(PID);
        totalDeposits = 0;
    }

    function rescueDeployedFunds(uint256 minReturnAmountAccepted, bool disableDeposits) external override onlyOwner {
        uint256 balanceBefore = depositToken.balanceOf(address(this));
        stakingContract.emergencyWithdraw(PID);
        uint256 balanceAfter = depositToken.balanceOf(address(this));
        require(balanceAfter.sub(balanceBefore) >= minReturnAmountAccepted, "JoeStrategyV4::rescueDeployedFunds");
        totalDeposits = balanceAfter;
        emit Reinvest(totalDeposits, totalSupply);
        if (DEPOSITS_ENABLED == true && disableDeposits == true) {
            updateDepositsEnabled(false);
        }
    }
}
