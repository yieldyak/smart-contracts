// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../interfaces/IPair.sol";
import "../lib/DexLibrary.sol";
import "./MasterChefVariableRewardsStrategy.sol";

/**
 * @notice Adapter strategy for MasterChef with LP deposit.
 */
abstract contract MasterChefVariableRewardsStrategyForLP is MasterChefVariableRewardsStrategy {
    using SafeMath for uint256;

    struct SwapPairs {
        address poolReward;
        address token0;
        address token1;
    }

    address private swapPairToken0;
    address private swapPairToken1;

    constructor(
        string memory _name,
        address _poolRewardToken,
        SwapPairs memory _swapPairs,
        ExtraReward[] memory _extraRewards,
        address _stakingContract,
        address _timelock,
        uint256 _pid,
        StrategySettings memory _strategySettings
    )
        MasterChefVariableRewardsStrategy(
            _name,
            _poolRewardToken,
            _swapPairs.poolReward,
            _extraRewards,
            _stakingContract,
            _timelock,
            _pid,
            _strategySettings
        )
    {
        assignSwapPairSafely(_swapPairs, _strategySettings.rewardToken, _poolRewardToken);
    }

    /**
     * @notice Initialization helper for Pair deposit tokens
     * @dev Checks that selected Pairs are valid for trading reward tokens
     * @dev Assigns values to IPair(swapPairToken0) and IPair(swapPairToken1)
     */
    function assignSwapPairSafely(
        SwapPairs memory _swapPairs,
        address _ecosystemToken,
        address _poolRewardToken
    ) private {
        if (
            _ecosystemToken != IPair(address(depositToken)).token0() &&
            _ecosystemToken != IPair(address(depositToken)).token1()
        ) {
            // deployment checks for non-pool2
            require(_swapPairs.token0 > address(0), "Swap pair 0 is necessary but not supplied");
            require(_swapPairs.token1 > address(0), "Swap pair 1 is necessary but not supplied");
            swapPairToken0 = _swapPairs.token0;
            swapPairToken1 = _swapPairs.token1;
            require(
                IPair(swapPairToken0).token0() == _ecosystemToken || IPair(swapPairToken0).token1() == _ecosystemToken,
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
        } else if (_ecosystemToken == IPair(address(depositToken)).token0()) {
            swapPairToken1 = address(depositToken);
        } else if (_ecosystemToken == IPair(address(depositToken)).token1()) {
            swapPairToken0 = address(depositToken);
        }
        if (_poolRewardToken == IPair(_swapPairs.poolReward).token0()) {
            require(
                IPair(_swapPairs.poolReward).token1() == _ecosystemToken,
                "Swap pair swapPairPoolReward does not contain reward token"
            );
        } else {
            require(
                IPair(_swapPairs.poolReward).token0() == _ecosystemToken &&
                    IPair(_swapPairs.poolReward).token1() == _poolRewardToken,
                "Swap pair swapPairPoolReward does not contain reward token"
            );
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
