// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../../../lib/SafeMath.sol";
import "../../../../interfaces/IWGAS.sol";

import "../interfaces/IKyberPair.sol";

library KyberDexLibrary {
    using SafeMath for uint256;
    bytes private constant zeroBytes = new bytes(0);
    uint256 private constant PRECISION = 1e18;
    IWGAS private constant WAVAX = IWGAS(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);

    /**
     * @notice Swap directly through a Pair
     * @param amountIn input amount
     * @param fromToken address
     * @param toToken address
     * @param pair Pair used for swap
     * @return output amount
     */
    function swap(
        uint256 amountIn,
        address fromToken,
        address toToken,
        IKyberPair pair
    ) internal returns (uint256) {
        (address token0, ) = sortTokens(fromToken, toToken);
        (, , uint112 reserve0, uint112 reserve1, uint256 feeInPrecision) = pair.getTradeInfo();
        if (token0 != fromToken) (reserve0, reserve1) = (reserve1, reserve0);
        uint256 amountOut1 = 0;
        uint256 amountOut2 = getAmountOut(amountIn, reserve0, reserve1, feeInPrecision);
        if (token0 != fromToken) (amountOut1, amountOut2) = (amountOut2, amountOut1);
        safeTransfer(fromToken, address(pair), amountIn);
        pair.swap(amountOut1, amountOut2, address(this), zeroBytes);
        return amountOut2 > amountOut1 ? amountOut2 : amountOut1;
    }

    function checkSwapPairCompatibility(
        IKyberPair pair,
        address tokenA,
        address tokenB
    ) internal pure returns (bool) {
        return
            (tokenA == pair.token0() || tokenA == pair.token1()) &&
            (tokenB == pair.token0() || tokenB == pair.token1()) &&
            tokenA != tokenB;
    }

    function estimateConversionThroughPair(
        uint256 amountIn,
        address fromToken,
        address toToken,
        IKyberPair swapPair
    ) internal view returns (uint256) {
        (address token0, ) = sortTokens(fromToken, toToken);
        (, , uint112 reserve0, uint112 reserve1, uint256 feeInPrecision) = swapPair.getTradeInfo();
        if (token0 != fromToken) (reserve0, reserve1) = (reserve1, reserve0);
        return getAmountOut(amountIn, reserve0, reserve1, feeInPrecision);
    }

    /**
     * @notice Converts reward tokens to deposit tokens
     * @dev No price checks enforced
     * @param amount reward tokens
     * @return deposit tokens
     */
    function convertRewardTokensToDepositTokens(
        uint256 amount,
        address rewardToken,
        address depositToken,
        IKyberPair swapPairToken0,
        IKyberPair swapPairToken1
    ) internal returns (uint256) {
        uint256 amountIn = amount.div(2);
        require(amountIn > 0, "KyberDexLibrary::_convertRewardTokensToDepositTokens");

        address token0 = IKyberPair(depositToken).token0();
        uint256 amountOutToken0 = amountIn;
        if (rewardToken != token0) {
            amountOutToken0 = KyberDexLibrary.swap(amountIn, rewardToken, token0, swapPairToken0);
        }

        address token1 = IKyberPair(depositToken).token1();
        uint256 amountOutToken1 = amountIn;
        if (rewardToken != token1) {
            amountOutToken1 = KyberDexLibrary.swap(amountIn, rewardToken, token1, swapPairToken1);
        }

        return KyberDexLibrary.addLiquidity(depositToken, amountOutToken0, amountOutToken1);
    }

    /**
     * @notice Add liquidity directly through a Pair
     * @dev Checks adding the max of each token amount
     * @param depositToken address
     * @param maxAmountIn0 amount token0
     * @param maxAmountIn1 amount token1
     * @return liquidity tokens
     */
    function addLiquidity(
        address depositToken,
        uint256 maxAmountIn0,
        uint256 maxAmountIn1
    ) internal returns (uint256) {
        (uint112 reserve0, uint112 reserve1) = IKyberPair(address(depositToken)).getReserves();
        uint256 amountIn1 = _quoteLiquidityAmountOut(maxAmountIn0, reserve0, reserve1);
        if (amountIn1 > maxAmountIn1) {
            amountIn1 = maxAmountIn1;
            maxAmountIn0 = _quoteLiquidityAmountOut(maxAmountIn1, reserve1, reserve0);
        }

        safeTransfer(IKyberPair(depositToken).token0(), depositToken, maxAmountIn0);
        safeTransfer(IKyberPair(depositToken).token1(), depositToken, amountIn1);
        return IKyberPair(depositToken).mint(address(this));
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
     * @notice Given two tokens, it'll return the tokens in the right order for the tokens pair
     * @dev TokenA must be different from TokenB, and both shouldn't be address(0), no validations
     * @param tokenA address
     * @param tokenB address
     * @return sorted tokens
     */
    function sortTokens(address tokenA, address tokenB) internal pure returns (address, address) {
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
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut,
        uint256 feeInPrecision
    ) internal pure returns (uint256) {
        uint256 amountInWithFee = amountIn.mul(PRECISION.sub(feeInPrecision)).div(PRECISION);
        uint256 numerator = amountInWithFee.mul(reserveOut);
        uint256 denominator = reserveIn.add(amountInWithFee);
        return numerator.div(denominator);
    }

    /**
     * @notice Safely transfer using an anonymous ERC20 token
     * @dev Requires token to return true on transfer
     * @param token address
     * @param to recipient address
     * @param value amount
     */
    function safeTransfer(
        address token,
        address to,
        uint256 value
    ) internal {
        require(IERC20(token).transfer(to, value), "KyberDexLibrary::TRANSFER_FROM_FAILED");
    }
}
