// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../interfaces/IPair.sol";
import "../lib/DexLibrary.sol";
import "./VariableRewardsStrategyV2.sol";

/**
 * @notice Adapter strategy for VariableRewardsStrategy with SA deposit.
 */
abstract contract VariableRewardsStrategyForLPV2 is VariableRewardsStrategyV2 {
    struct SwapPairs {
        address token0;
        address token1;
    }

    address private swapPairToken0;
    address private swapPairToken1;

    constructor(
        SwapPairs memory _swapPairs,
        RewardSwapPairs[] memory _rewardSwapPairs,
        BaseSettings memory _baseSettings,
        StrategySettings memory _strategySettings
    ) VariableRewardsStrategyV2(_rewardSwapPairs, _baseSettings, _strategySettings) {
        assignSwapPairSafely(_swapPairs);
    }

    /**
     * @notice Initialization helper for Pair deposit tokens
     * @dev Checks that selected Pairs are valid for trading reward tokens
     * @dev Assigns values to IPair(swapPairToken0) and IPair(swapPairToken1)
     */
    function assignSwapPairSafely(SwapPairs memory _swapPairs) private {
        if (address(WAVAX) != IPair(asset).token0() && address(WAVAX) != IPair(asset).token1()) {
            // deployment checks for non-pool2
            require(_swapPairs.token0 > address(0), "Swap pair 0 is necessary but not supplied");
            require(_swapPairs.token1 > address(0), "Swap pair 1 is necessary but not supplied");
            swapPairToken0 = _swapPairs.token0;
            swapPairToken1 = _swapPairs.token1;
            require(
                IPair(swapPairToken0).token0() == address(WAVAX) || IPair(swapPairToken0).token1() == address(WAVAX),
                "Swap pair supplied does not have the reward token as one of it's pair"
            );
            require(
                IPair(swapPairToken0).token0() == IPair(asset).token0() ||
                    IPair(swapPairToken0).token1() == IPair(asset).token0(),
                "Swap pair 0 supplied does not match the pair in question"
            );
            require(
                IPair(swapPairToken1).token0() == IPair(asset).token1() ||
                    IPair(swapPairToken1).token1() == IPair(asset).token1(),
                "Swap pair 1 supplied does not match the pair in question"
            );
        } else if (address(WAVAX) == IPair(asset).token0()) {
            swapPairToken1 = asset;
        } else if (address(WAVAX) == IPair(asset).token1()) {
            swapPairToken0 = asset;
        }
    }

    /* VIRTUAL */
    function _convertRewardTokenToDepositToken(uint256 fromAmount) internal override returns (uint256 toAmount) {
        toAmount = DexLibrary.convertRewardTokensToDepositTokens(
            fromAmount,
            rewardToken,
            asset,
            IPair(swapPairToken0),
            IPair(swapPairToken1)
        );
    }
}
