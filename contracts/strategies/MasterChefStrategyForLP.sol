// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "../interfaces/IPair.sol";
import "../lib/DexLibrary.sol";
import "./MasterChefStrategy.sol";

/**
 * @notice Adapter strategy for MasterChef with LP deposit.
 */
abstract contract MasterChefStrategyForLP is MasterChefStrategy {
    using SafeMath for uint256;

    address private swapPairToken0;
    address private swapPairToken1;

    constructor(
        string memory _name,
        address _depositToken,
        address _rewardToken,
        address _swapPairToken0,
        address _swapPairToken1,
        address _stakingRewards,
        address _timelock,
        uint256 _pid,
        uint256 _minTokensToReinvest,
        uint256 _adminFeeBips,
        uint256 _devFeeBips,
        uint256 _reinvestRewardBips
    )
        MasterChefStrategy(
            _name,
            _depositToken,
            _rewardToken,
            _stakingRewards,
            _timelock,
            _pid,
            _minTokensToReinvest,
            _adminFeeBips,
            _devFeeBips,
            _reinvestRewardBips
        )
    {
        assignSwapPairSafely(swapPairToken0, swapPairToken1, _rewardToken);
    }

    /**
     * @notice Initialization helper for Pair deposit tokens
     * @dev Checks that selected Pairs are valid for trading reward tokens
     * @dev Assigns values to IPair(swapPairToken0) and IPair(swapPairToken1)
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
            swapPairToken0 = _swapPairToken0;
            swapPairToken1 = _swapPairToken1;
            require(
                IPair(swapPairToken0).token0() == _rewardToken || IPair(swapPairToken0).token1() == _rewardToken,
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
        } else if (_rewardToken == IPair(address(depositToken)).token0()) {
            swapPairToken1 = address(depositToken);
        } else if (_rewardToken == IPair(address(depositToken)).token1()) {
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
