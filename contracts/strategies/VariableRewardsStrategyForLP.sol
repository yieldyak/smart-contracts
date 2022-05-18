// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../interfaces/IPair.sol";
import "../lib/DexLibrary.sol";
import "./VariableRewardsStrategy.sol";

/**
 * @notice Adapter strategy for VariableRewardsStrategy with SA deposit.
 */
abstract contract VariableRewardsStrategyForLP is VariableRewardsStrategy {
    struct SwapPairs {
        address token0;
        address token1;
    }

    address private swapPairToken0;
    address private swapPairToken1;

    constructor(
        string memory _name,
        address _depositToken,
        SwapPairs memory _swapPairs,
        RewardSwapPairs[] memory _rewardSwapPairs,
        address _timelock,
        StrategySettings memory _strategySettings
    ) VariableRewardsStrategy(_name, _depositToken, _rewardSwapPairs, _timelock, _strategySettings) {
        assignSwapPairSafely(_swapPairs);
    }

    /**
     * @notice Initialization helper for Pair deposit tokens
     * @dev Checks that selected Pairs are valid for trading reward tokens
     * @dev Assigns values to IPair(swapPairToken0) and IPair(swapPairToken1)
     */
    function assignSwapPairSafely(SwapPairs memory _swapPairs) private {
        if (
            address(WAVAX) != IPair(address(depositToken)).token0() &&
            address(WAVAX) != IPair(address(depositToken)).token1()
        ) {
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
                IPair(swapPairToken0).token0() == IPair(address(depositToken)).token0() ||
                    IPair(swapPairToken0).token1() == IPair(address(depositToken)).token0(),
                "Swap pair 0 supplied does not match the pair in question"
            );
            require(
                IPair(swapPairToken1).token0() == IPair(address(depositToken)).token1() ||
                    IPair(swapPairToken1).token1() == IPair(address(depositToken)).token1(),
                "Swap pair 1 supplied does not match the pair in question"
            );
        } else if (address(WAVAX) == IPair(address(depositToken)).token0()) {
            swapPairToken1 = address(depositToken);
        } else if (address(WAVAX) == IPair(address(depositToken)).token1()) {
            swapPairToken0 = address(depositToken);
        }
    }

    /* VIRTUAL */
    function _convertRewardTokenToDepositToken(uint256 fromAmount) internal override returns (uint256 toAmount) {
        toAmount = DexLibrary.convertRewardTokensToDepositTokens(
            fromAmount,
            address(rewardToken),
            address(depositToken),
            IPair(swapPairToken0),
            IPair(swapPairToken1)
        );
    }
}
