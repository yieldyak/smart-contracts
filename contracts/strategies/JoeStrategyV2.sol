// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "../YakStrategy.sol";
import "../interfaces/IJoeChef.sol";
import "../interfaces/IPair.sol";
import "../interfaces/IWAVAX.sol";
import "../interfaces/IERC20.sol";

/**
 * @notice Strategy for Trader Joe, which includes optional and variable extra rewards
 * @dev Fees are paid in WAVAX
 */
contract JoeStrategyV2 is YakStrategy {
    using SafeMath for uint;

    IJoeChef public stakingContract;
    IPair private swapPairWAVAXJoe;
    IPair private swapPairExtraToken;
    IPair private swapPairToken0;
    IPair private swapPairToken1;
    IERC20 private poolRewardToken;
    uint private PID;
    IWAVAX private constant WAVAX = IWAVAX(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);
    bytes private constant zeroBytes = new bytes(0);

    constructor (
        string memory _name,
        address _depositToken,
        address _poolRewardToken,
        address _rewardToken,
        address _stakingContract,
        address _swapPairWAVAXJoe,
        address _swapPairToken0,
        address _swapPairToken1,
        address _extraTokenSwapPair,
        uint pid,
        address _timelock,
        uint _minTokensToReinvest,
        uint _adminFeeBips,
        uint _devFeeBips,
        uint _reinvestRewardBips
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
    function assignSwapPairSafely(address _swapPairWAVAXJoe, address _extraTokenSwapPair, address _swapPairToken0, address _swapPairToken1) private {
        require(
            _checkSwapPairCompatibility(IPair(_swapPairWAVAXJoe), address(WAVAX), address(poolRewardToken)),
            "_swapPairWAVAXJoe is not a WAVAX-Joe pair"
        );
        require(
            _swapPairToken0 == address(0)
            || _checkSwapPairCompatibility(IPair(_swapPairToken0), address(WAVAX), IPair(address(depositToken)).token0()),
            "_swapPairToken0 is not a WAVAX+deposit token0"
        );
        require(
            _swapPairToken1 == address(0)
            || _checkSwapPairCompatibility(IPair(_swapPairToken1), address(WAVAX), IPair(address(depositToken)).token1()),
            "_swapPairToken0 is not a WAVAX+deposit token1"
        );
        ( ,address extraRewardToken, , ) = stakingContract.pendingTokens(PID, address(this));
        require(
            _extraTokenSwapPair == address(0)
            || _checkSwapPairCompatibility(IPair(_extraTokenSwapPair), address(WAVAX), extraRewardToken),
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

    function deposit(uint amount) external override {
        _deposit(msg.sender, amount);
    }

    function depositWithPermit(uint amount, uint deadline, uint8 v, bytes32 r, bytes32 s) external override {
        depositToken.permit(msg.sender, address(this), amount, deadline, v, r, s);
        _deposit(msg.sender, amount);
    }

    function depositFor(address account, uint amount) external override {
        _deposit(account, amount);
    }

    function _deposit(address account, uint amount) private onlyAllowedDeposits {
        require(DEPOSITS_ENABLED == true, "JoeStrategyV2::_deposit");
        if (MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST > 0) {
            uint unclaimedRewards = checkReward();
            if (unclaimedRewards > MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST) {
                (uint poolTokenAmount, address extraRewardTokenAddress, uint extraRewardTokenAmount, uint rewardTokenAmount) = _checkReward();
                _reinvest(poolTokenAmount, extraRewardTokenAddress, extraRewardTokenAmount, rewardTokenAmount);
            }
        }
        require(depositToken.transferFrom(msg.sender, address(this), amount));
        _stakeDepositTokens(amount);
        _mint(account, getSharesForDepositTokens(amount));
        totalDeposits = totalDeposits.add(amount);
        emit Deposit(account, amount);
    }

    function withdraw(uint amount) external override {
        uint depositTokenAmount = getDepositTokensForShares(amount);
        if (depositTokenAmount > 0) {
            _withdrawDepositTokens(depositTokenAmount);
            _safeTransfer(address(depositToken), msg.sender, depositTokenAmount);
            _burn(msg.sender, amount);
            totalDeposits = totalDeposits.sub(depositTokenAmount);
            emit Withdraw(msg.sender, depositTokenAmount);
        }
    }

    function _withdrawDepositTokens(uint amount) private {
        require(amount > 0, "JoeStrategyV2::_withdrawDepositTokens");
        stakingContract.withdraw(PID, amount);
    }

    function reinvest() external override onlyEOA {
        uint unclaimedRewards = checkReward();
        require(unclaimedRewards >= MIN_TOKENS_TO_REINVEST, "JoeStrategyV2::reinvest");
        (uint poolTokenAmount, address extraRewardTokenAddress, uint extraRewardTokenAmount, uint rewardTokenAmount) = _checkReward();
        _reinvest(poolTokenAmount, extraRewardTokenAddress, extraRewardTokenAmount, rewardTokenAmount);
    }

    function _checkSwapPairCompatibility(IPair pair, address tokenA, address tokenB) private view returns(bool) {
        return (tokenA == pair.token0() || tokenA == pair.token1()) && (tokenB == pair.token0() || tokenB == pair.token1()) && tokenA != tokenB;
    }

    function _convertRewardIntoWAVAX(uint pendingJoe, address extraRewardToken, uint pendingExtraReward) private returns (uint) {
        uint convertedAmountWAVAX = 0;
        
        if (extraRewardToken == address(poolRewardToken)) {
            convertedAmountWAVAX = _swap(
                pendingExtraReward.add(pendingJoe),
                address(poolRewardToken), address(WAVAX),
                swapPairWAVAXJoe
            );
            return convertedAmountWAVAX;
        }

        convertedAmountWAVAX = _swap(
            pendingJoe,
            address(poolRewardToken), address(WAVAX),
            swapPairWAVAXJoe
        );
        if (
            address(swapPairExtraToken) != address(0)
            && pendingExtraReward > 0 
            && _checkSwapPairCompatibility(swapPairExtraToken, extraRewardToken, address(WAVAX))
        ) {
            convertedAmountWAVAX = convertedAmountWAVAX.add(
                _swap(pendingExtraReward, extraRewardToken, address(WAVAX), swapPairExtraToken)
            );
        }
        return convertedAmountWAVAX;
    }

    /**
     * @notice Reinvest rewards from staking contract to deposit tokens
     * @dev Reverts if the expected amount of tokens are not returned from `stakingContract`
     */
    function _reinvest(uint _pendingJoe, address _extraRewardToken, uint _pendingExtraToken, uint _pendingWavax) private {
        stakingContract.deposit(PID, 0);
        uint amount = _pendingWavax.add(
            _convertRewardIntoWAVAX(_pendingJoe, _extraRewardToken, _pendingExtraToken)
        );
        
        uint devFee = amount.mul(DEV_FEE_BIPS).div(BIPS_DIVISOR);
        if (devFee > 0) {
            _safeTransfer(address(WAVAX), devAddr, devFee);
        }

        uint adminFee = amount.mul(ADMIN_FEE_BIPS).div(BIPS_DIVISOR);
        if (adminFee > 0) {
            _safeTransfer(address(WAVAX), owner(), adminFee);
        }

        uint reinvestFee = amount.mul(REINVEST_REWARD_BIPS).div(BIPS_DIVISOR);
        if (reinvestFee > 0) {
            _safeTransfer(address(WAVAX), msg.sender, reinvestFee);
        }

        uint depositTokenAmount = _convertWAVAXToDepositTokens(
            amount.sub(devFee).sub(adminFee).sub(reinvestFee)
        );

        _stakeDepositTokens(depositTokenAmount);
        totalDeposits = totalDeposits.add(depositTokenAmount);

        emit Reinvest(totalDeposits, totalSupply);
    }
    
    function _stakeDepositTokens(uint amount) private {
        require(amount > 0, "JoeStrategyV2::_stakeDepositTokens");
        stakingContract.deposit(PID, amount);
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
    function _getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) private pure returns (uint) {
        uint amountInWithFee = amountIn.mul(997);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        return numerator.div(denominator);
    }

    /**
     * @notice Safely transfer using an anonymous ERC20 token
     * @dev Requires token to return true on transfer
     * @param token address
     * @param to recipient address
     * @param value amount
     */
    function _safeTransfer(address token, address to, uint256 value) private {
        require(IERC20(token).transfer(to, value), 'JoeStrategyV2::TRANSFER_FROM_FAILED');
    }

    /**
     * @notice Quote liquidity amount out
     * @param amountIn input tokens
     * @param reserve0 size of input asset reserve
     * @param reserve1 size of output asset reserve
     * @return liquidity tokens
     */
    function _quoteLiquidityAmountOut(uint amountIn, uint reserve0, uint reserve1) private pure returns (uint) {
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
    function _addLiquidity(address token0, address token1, uint maxAmountIn0, uint maxAmountIn1) private returns (uint) {
        (uint112 reserve0, uint112 reserve1,) = IPair(address(depositToken)).getReserves();
        uint amountIn1 = _quoteLiquidityAmountOut(maxAmountIn0, reserve0, reserve1);
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
    function _swap(uint amountIn, address fromToken, address toToken, IPair pair) private returns (uint) {
        (address token0,) = _sortTokens(fromToken, toToken);
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        if (token0 != fromToken) (reserve0, reserve1) = (reserve1, reserve0);
        uint amountOut1 = 0;
        uint amountOut2 = _getAmountOut(amountIn, reserve0, reserve1);
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
    function _convertWAVAXToDepositTokens(uint amount) private returns (uint) {
        uint amountIn = amount.div(2);
        require(amountIn > 0, "JoeStrategyV2::_convertRewardTokensToDepositTokens");

        address token0 = IPair(address(depositToken)).token0();
        uint amountOutToken0 = amountIn;
        if (address(WAVAX) != token0) {
            amountOutToken0 = _swap(amountIn, address(WAVAX), token0, swapPairToken0);
        }

        address token1 = IPair(address(depositToken)).token1();
        uint amountOutToken1 = amountIn;
        if (address(WAVAX) != token1) {
            amountOutToken1 = _swap(amountIn, address(WAVAX), token1, swapPairToken1);
        }

        return _addLiquidity(token0, token1, amountOutToken0, amountOutToken1);
    }

    function setExtraRewardSwapPair(address swapPair) external onlyDev {
        if (swapPair == address(0)) {
            swapPairExtraToken = IPair(address(0));
            return;
        }

        ( ,address extraRewardToken, , ) = stakingContract.pendingTokens(PID, address(this));
        require(
            _checkSwapPairCompatibility(IPair(swapPair), address(WAVAX), extraRewardToken),
            "_swapPairWAVAXJoe is not a WAVAX-extra reward pair, check stakingContract.pendingTokens"
        );
        swapPairExtraToken = IPair(swapPair);
    }

    function _estimateConversionIntoRewardToken(uint amountIn, address fromToken, address toToken, IPair swapPair) private view returns (uint) {
        (address token0,) = _sortTokens(fromToken, toToken);
        (uint112 reserve0, uint112 reserve1,) = swapPair.getReserves();
        if (token0 != fromToken) (reserve0, reserve1) = (reserve1, reserve0);
        return _getAmountOut(amountIn, reserve0, reserve1);
    }

    function _checkReward() private view returns (uint poolTokenAmount, address extraRewardTokenAddress, uint extraRewardTokenAmount, uint rewardTokenAmount) {
        (uint pendingJoe, address extraRewardToken, , uint pendingExtraToken) = stakingContract.pendingTokens(PID, address(this));
        uint poolRewardBalance = poolRewardToken.balanceOf(address(this));
        uint extraRewardTokenBalance;
        if (extraRewardToken != address(0)) {
            extraRewardTokenBalance = IERC20(extraRewardToken).balanceOf(address(this));
        }
        uint rewardTokenBalance = rewardToken.balanceOf(address(this));
        return (
            poolRewardBalance.add(pendingJoe),
            extraRewardToken,
            extraRewardTokenBalance.add(pendingExtraToken),
            rewardTokenBalance
        );
    }
    
    function checkReward() public override view returns (uint) {
        (uint poolTokenAmount, address extraRewardTokenAddress, uint extraRewardTokenAmount, uint rewardTokenAmount) = _checkReward();
        uint estimatedWAVAX = _estimateConversionIntoRewardToken(
            poolTokenAmount, 
            address(poolRewardToken), address(WAVAX),
            swapPairWAVAXJoe
        );
        if (
            address(swapPairExtraToken) != address(0)
            && extraRewardTokenAmount > 0 
            && _checkSwapPairCompatibility(swapPairExtraToken, extraRewardTokenAddress, address(WAVAX))
        ) {
            estimatedWAVAX.add(
                _estimateConversionIntoRewardToken(
                    extraRewardTokenAmount,
                    extraRewardTokenAddress, address(WAVAX),
                    swapPairExtraToken
                )
            );
        }
        return rewardTokenAmount.add(estimatedWAVAX);
    }

    function estimateDeployedBalance() external override view returns (uint) {
        (uint amount, ) = stakingContract.userInfo(PID, address(this));
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

    function rescueDeployedFunds(uint minReturnAmountAccepted, bool disableDeposits) external override onlyOwner {
        uint balanceBefore = depositToken.balanceOf(address(this));
        stakingContract.emergencyWithdraw(PID);
        uint balanceAfter = depositToken.balanceOf(address(this));
        require(balanceAfter.sub(balanceBefore) >= minReturnAmountAccepted, "JoeStrategyV2::rescueDeployedFunds");
        totalDeposits = balanceAfter;
        emit Reinvest(totalDeposits, totalSupply);
        if (DEPOSITS_ENABLED == true && disableDeposits == true) {
            updateDepositsEnabled(false);
        }
    }
}