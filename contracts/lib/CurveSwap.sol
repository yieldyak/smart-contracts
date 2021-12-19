// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./DexLibrary.sol";
import "../interfaces/IPair.sol";
import "../interfaces/ICurveCryptoSwap.sol";
import "../interfaces/ICurveStableSwap.sol";
import "../interfaces/ICurveStableSwapAave.sol";
import "../interfaces/ICurveBtcSwap.sol";

library CurveSwap {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    enum PoolType {
        AAVE,
        CRYPTO,
        BTC,
        STABLE
    }

    struct Settings {
        PoolType poolType;
        address swapPairRewardZap;
        address zapToken;
        address zapContract;
        uint256 zapTokenIndex;
        uint256 maxSlippage;
    }

    uint256 private constant BIPS_DIVISOR = 10000;

    function zapToAaveLP(
        uint256 amount,
        address rewardToken,
        address, /* depositToken */
        Settings memory zapSettings
    ) internal returns (uint256) {
        uint256 zapTokenAmount = DexLibrary.swap(
            amount,
            rewardToken,
            zapSettings.zapToken,
            IPair(zapSettings.swapPairRewardZap)
        );
        uint256[3] memory amounts = [uint256(0), uint256(0), uint256(0)];
        amounts[zapSettings.zapTokenIndex] = zapTokenAmount;
        uint256 expectedAmount = ICurveStableSwapAave(zapSettings.zapContract).calc_token_amount(amounts, true);
        uint256 slippage = expectedAmount.mul(zapSettings.maxSlippage).div(BIPS_DIVISOR);
        return ICurveStableSwapAave(zapSettings.zapContract).add_liquidity(amounts, expectedAmount.sub(slippage), true);
    }

    function zapToStableLP(
        uint256 amount,
        address rewardToken,
        address, /* depositToken */
        Settings memory zapSettings
    ) internal returns (uint256) {
        uint256 zapTokenAmount = DexLibrary.swap(
            amount,
            rewardToken,
            zapSettings.zapToken,
            IPair(zapSettings.swapPairRewardZap)
        );
        uint256[3] memory amounts = [uint256(0), uint256(0), uint256(0)];
        amounts[zapSettings.zapTokenIndex] = zapTokenAmount;
        uint256 expectedAmount = ICurveStableSwap(zapSettings.zapContract).calc_token_amount(amounts, true);
        uint256 slippage = expectedAmount.mul(zapSettings.maxSlippage).div(BIPS_DIVISOR);
        return ICurveStableSwap(zapSettings.zapContract).add_liquidity(amounts, expectedAmount.sub(slippage));
    }

    function zapToCryptoLP(
        uint256 amount,
        address rewardToken,
        address depositToken,
        Settings memory zapSettings
    ) internal returns (uint256) {
        uint256 zapTokenAmount = DexLibrary.swap(
            amount,
            rewardToken,
            zapSettings.zapToken,
            IPair(zapSettings.swapPairRewardZap)
        );
        uint256[5] memory amounts = [uint256(0), uint256(0), uint256(0), uint256(0), uint256(0)];
        amounts[zapSettings.zapTokenIndex] = zapTokenAmount;
        uint256 expectedAmount = ICurveCryptoSwap(zapSettings.zapContract).calc_token_amount(amounts, true);
        uint256 slippage = expectedAmount.mul(zapSettings.maxSlippage).div(BIPS_DIVISOR);
        ICurveCryptoSwap(zapSettings.zapContract).add_liquidity(amounts, expectedAmount.sub(slippage));
        return IERC20(depositToken).balanceOf(address(this));
    }

    function zapToTwoPoolLP(
        uint256 amount,
        address rewardToken,
        address depositToken,
        Settings memory zapSettings
    ) internal returns (uint256) {
        uint256 zapTokenAmount = DexLibrary.swap(
            amount,
            rewardToken,
            zapSettings.zapToken,
            IPair(zapSettings.swapPairRewardZap)
        );
        uint256[2] memory amounts = [uint256(0), uint256(0)];
        amounts[zapSettings.zapTokenIndex] = zapTokenAmount;
        uint256 expectedAmount = ICurveBtcSwap(zapSettings.zapContract).calc_token_amount(amounts, true);
        uint256 slippage = expectedAmount.mul(zapSettings.maxSlippage).div(BIPS_DIVISOR);
        ICurveBtcSwap(zapSettings.zapContract).add_liquidity(amounts, expectedAmount.sub(slippage), true);
        return IERC20(depositToken).balanceOf(address(this));
    }

    function setZap(Settings memory zapSettings)
        internal
        view
        returns (function(uint256, address, address, Settings memory) returns (uint256))
    {
        function(uint256, address, address, Settings memory) returns (uint256) zapFunction;
        if (zapSettings.poolType == CurveSwap.PoolType.AAVE) {
            require(
                zapSettings.zapToken ==
                    ICurveStableSwap(zapSettings.zapContract).underlying_coins(zapSettings.zapTokenIndex),
                "Wrong zap token index"
            );
            zapFunction = zapToAaveLP;
        } else if (zapSettings.poolType == CurveSwap.PoolType.CRYPTO) {
            require(
                zapSettings.zapToken ==
                    ICurveCryptoSwap(zapSettings.zapContract).underlying_coins(zapSettings.zapTokenIndex),
                "Wrong zap token index"
            );
            zapFunction = zapToCryptoLP;
        } else if (zapSettings.poolType == CurveSwap.PoolType.BTC) {
            require(
                zapSettings.zapToken ==
                    ICurveBtcSwap(zapSettings.zapContract).underlying_coins(zapSettings.zapTokenIndex),
                "Wrong zap token index"
            );
            zapFunction = zapToTwoPoolLP;
        }
        return zapFunction;
    }
}
