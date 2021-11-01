// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "../YakStrategy.sol";
import "../interfaces/IStakingRewards.sol";
import "../interfaces/IPair.sol";

/**
 * @notice Pool2 strategy for StakingRewards
 */
contract DexStrategyV5 is YakStrategy {
    using SafeMath for uint256;

    IStakingRewards public stakingContract;
    IPair private swapPairToken0;
    IPair private swapPairToken1;
    bytes private constant zeroBytes = new bytes(0);

    constructor(
        string memory _name,
        address _depositToken,
        address _rewardToken,
        address _stakingContract,
        address _swapPairToken0,
        address _swapPairToken1,
        address _timelock,
        uint256 _minTokensToReinvest,
        uint256 _adminFeeBips,
        uint256 _devFeeBips,
        uint256 _reinvestRewardBips
    ) {
        name = _name;
        depositToken = IERC20(_depositToken);
        rewardToken = IERC20(_rewardToken);
        stakingContract = IStakingRewards(_stakingContract);
        devAddr = msg.sender;

        assignSwapPairSafely(_swapPairToken0, _swapPairToken1, _rewardToken);
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
        address _swapPairToken0,
        address _swapPairToken1,
        address _rewardToken
    ) private {
        if (
            _rewardToken != IPair(address(depositToken)).token0() &&
            _rewardToken != IPair(address(depositToken)).token1()
        ) {
            // deployment checks for non-pool2
            require(_swapPairToken0 > address(0), "Swap pair 0 is necessary but not supplied");
            require(_swapPairToken1 > address(0), "Swap pair 1 is necessary but not supplied");
            swapPairToken0 = IPair(_swapPairToken0);
            swapPairToken1 = IPair(_swapPairToken1);
            require(
                swapPairToken0.token0() == _rewardToken || swapPairToken0.token1() == _rewardToken,
                "Swap pair supplied does not have the reward token as one of it's pair"
            );
            require(
                swapPairToken0.token0() == IPair(address(depositToken)).token0() ||
                    swapPairToken0.token1() == IPair(address(depositToken)).token0(),
                "Swap pair 0 supplied does not match the pair in question"
            );
            require(
                swapPairToken1.token0() == IPair(address(depositToken)).token1() ||
                    swapPairToken1.token1() == IPair(address(depositToken)).token1(),
                "Swap pair 1 supplied does not match the pair in question"
            );
        } else if (_rewardToken == IPair(address(depositToken)).token0()) {
            swapPairToken1 = IPair(address(depositToken));
        } else if (_rewardToken == IPair(address(depositToken)).token1()) {
            swapPairToken0 = IPair(address(depositToken));
        }
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
        require(DEPOSITS_ENABLED == true, "DexStrategyV5::_deposit");
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
            _safeTransfer(address(depositToken), msg.sender, depositTokenAmount);
            _burn(msg.sender, amount);
            totalDeposits = totalDeposits.sub(depositTokenAmount);
            emit Withdraw(msg.sender, depositTokenAmount);
        }
    }

    function _withdrawDepositTokens(uint256 amount) private {
        require(amount > 0, "DexStrategyV5::_withdrawDepositTokens");
        stakingContract.withdraw(amount);
    }

    function reinvest() external override onlyEOA {
        uint256 unclaimedRewards = checkReward();
        require(unclaimedRewards >= MIN_TOKENS_TO_REINVEST, "DexStrategyV5::reinvest");
        _reinvest(unclaimedRewards);
    }

    /**
     * @notice Reinvest rewards from staking contract to deposit tokens
     * @dev Reverts if the expected amount of tokens are not returned from `stakingContract`
     * @param amount deposit tokens to reinvest
     */
    function _reinvest(uint256 amount) private {
        stakingContract.getReward();

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

        uint256 depositTokenAmount = _convertRewardTokensToDepositTokens(
            amount.sub(devFee).sub(adminFee).sub(reinvestFee)
        );

        _stakeDepositTokens(depositTokenAmount);
        totalDeposits = totalDeposits.add(depositTokenAmount);

        emit Reinvest(totalDeposits, totalSupply);
    }

    function _stakeDepositTokens(uint256 amount) private {
        require(amount > 0, "DexStrategyV5::_stakeDepositTokens");
        stakingContract.stake(amount);
    }

    /**
     * @notice Given two tokens, it'll return the tokens in the right order for the tokens pair
     * @dev TokenA must be different from TokenB, and both shouldn't be address(0), no validations
     * @param tokenA address
     * @param tokenB address
     * @return sorted tokens
     */
    function _sortTokens(address tokenA, address tokenB) private pure returns (address, address) {
        return tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    /**
     * @notice Given an input amount of an asset and pair reserves, returns maximum output amount of the other asset
     * @dev Assumes swap fee is 0.30%
     * @param amountIn input asset
     * @param reserveIn size of input asset reserve
     * @param reserveOut size of output asset reserve
     * @return maximum output amount
     */
    function _getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) private pure returns (uint256) {
        uint256 amountInWithFee = amountIn.mul(997);
        uint256 numerator = amountInWithFee.mul(reserveOut);
        uint256 denominator = reserveIn.mul(1000).add(amountInWithFee);
        return numerator.div(denominator);
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

    /**
     * @notice Quote liquidity amount out
     * @param amountIn input tokens
     * @param reserve0 size of input asset reserve
     * @param reserve1 size of output asset reserve
     * @return liquidity tokens
     */
    function _quoteLiquidityAmountOut(
        uint256 amountIn,
        uint256 reserve0,
        uint256 reserve1
    ) private pure returns (uint256) {
        return amountIn.mul(reserve1).div(reserve0);
    }

    /**
     * @notice Add liquidity directly through a Pair
     * @dev Checks adding the max of each token amount
     * @param token0 address
     * @param token1 address
     * @param maxAmountIn0 amount token0
     * @param maxAmountIn1 amount token1
     * @return liquidity tokens
     */
    function _addLiquidity(
        address token0,
        address token1,
        uint256 maxAmountIn0,
        uint256 maxAmountIn1
    ) private returns (uint256) {
        (uint112 reserve0, uint112 reserve1, ) = IPair(address(depositToken)).getReserves();
        uint256 amountIn1 = _quoteLiquidityAmountOut(maxAmountIn0, reserve0, reserve1);
        if (amountIn1 > maxAmountIn1) {
            amountIn1 = maxAmountIn1;
            maxAmountIn0 = _quoteLiquidityAmountOut(maxAmountIn1, reserve1, reserve0);
        }

        _safeTransfer(token0, address(depositToken), maxAmountIn0);
        _safeTransfer(token1, address(depositToken), amountIn1);
        return IPair(address(depositToken)).mint(address(this));
    }

    /**
     * @notice Swap directly through a Pair
     * @param amountIn input amount
     * @param fromToken address
     * @param toToken address
     * @param pair Pair used for swap
     * @return output amount
     */
    function _swap(
        uint256 amountIn,
        address fromToken,
        address toToken,
        IPair pair
    ) private returns (uint256) {
        (address token0, ) = _sortTokens(fromToken, toToken);
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        if (token0 != fromToken) (reserve0, reserve1) = (reserve1, reserve0);
        uint256 amountOut1 = 0;
        uint256 amountOut2 = _getAmountOut(amountIn, reserve0, reserve1);
        if (token0 != fromToken) (amountOut1, amountOut2) = (amountOut2, amountOut1);
        _safeTransfer(fromToken, address(pair), amountIn);
        pair.swap(amountOut1, amountOut2, address(this), zeroBytes);
        return amountOut2 > amountOut1 ? amountOut2 : amountOut1;
    }

    /**
     * @notice Converts reward tokens to deposit tokens
     * @dev No price checks enforced
     * @param amount reward tokens
     * @return deposit tokens
     */
    function _convertRewardTokensToDepositTokens(uint256 amount) private returns (uint256) {
        uint256 amountIn = amount.div(2);
        require(amountIn > 0, "DexStrategyV5::_convertRewardTokensToDepositTokens");

        address token0 = IPair(address(depositToken)).token0();
        uint256 amountOutToken0 = amountIn;
        if (address(rewardToken) != token0) {
            amountOutToken0 = _swap(amountIn, address(rewardToken), token0, swapPairToken0);
        }

        address token1 = IPair(address(depositToken)).token1();
        uint256 amountOutToken1 = amountIn;
        if (address(rewardToken) != token1) {
            amountOutToken1 = _swap(amountIn, address(rewardToken), token1, swapPairToken1);
        }

        return _addLiquidity(token0, token1, amountOutToken0, amountOutToken1);
    }

    function checkReward() public view override returns (uint256) {
        return stakingContract.earned(address(this));
    }

    function estimateDeployedBalance() external view override returns (uint256) {
        return stakingContract.balanceOf(address(this));
    }

    function rescueDeployedFunds(uint256 minReturnAmountAccepted, bool disableDeposits) external override onlyOwner {
        uint256 balanceBefore = depositToken.balanceOf(address(this));
        stakingContract.exit();
        uint256 balanceAfter = depositToken.balanceOf(address(this));
        require(balanceAfter.sub(balanceBefore) >= minReturnAmountAccepted, "DexStrategyV5::rescueDeployedFunds");
        totalDeposits = balanceAfter;
        emit Reinvest(totalDeposits, totalSupply);
        if (DEPOSITS_ENABLED == true && disableDeposits == true) {
            updateDepositsEnabled(false);
        }
    }
}
