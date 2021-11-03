// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "../interfaces/IPair.sol";
import "../lib/DexLibrary.sol";
import "./MasterChefStrategy.sol";

/**
 * @notice Adapter strategy for MasterChef with single-sided token deposit.
 */
abstract contract MasterChefStrategyForSA is MasterChefStrategy {
    using SafeMath for uint256;

    address private swapPairToken;

    constructor(
        string memory _name,
        address _depositToken,
        address _ecosystemToken,
        address _poolRewardToken,
        address _swapPairPoolReward,
        address _swapPairToken,
        address _stakingRewards,
        address _timelock,
        uint256 _pid,
        StrategySettings memory _strategySettings
    )
        MasterChefStrategy(
            _name,
            _depositToken,
            _ecosystemToken,
            _poolRewardToken,
            _swapPairPoolReward,
            _stakingRewards,
            _timelock,
            _pid,
            _strategySettings
        )
    {
        assignSwapPairSafely(_swapPairToken);
    }

    /**
     * @notice Initialization helper for Pair deposit tokens
     * @dev Checks that selected Pairs are valid for trading reward tokens
     * @dev Assigns values to swapPairToken
     */
    function assignSwapPairSafely(address _swapPairToken) private {
        require(
            DexLibrary.checkSwapPairCompatibility(IPair(_swapPairToken), address(depositToken), address(rewardToken)),
            "swap token does not match deposit and reward token"
        );
        swapPairToken = _swapPairToken;
    }

    /* VIRTUAL */
    function _convertRewardTokenToDepositToken(uint256 fromAmount) internal override returns (uint256 toAmount) {
        toAmount = DexLibrary.swap(fromAmount, address(rewardToken), address(depositToken), IPair(swapPairToken));
    }
}
