// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "../interfaces/IPair.sol";
import "../lib/DexLibrary.sol";
import "./MasterChefVariableRewardsStrategy.sol";

/**
 * @notice Adapter strategy for MasterChef with SA deposit.
 */
abstract contract MasterChefVariableRewardsStrategyForSA is MasterChefVariableRewardsStrategy {
    using SafeMath for uint256;

    address private swapPairToken;

    constructor(
        string memory _name,
        address _depositToken,
        address _ecosystemToken,
        address _poolRewardToken,
        address _swapPairToken,
        ExtraReward[] memory _extraRewards,
        address _stakingContract,
        address _timelock,
        uint256 _pid,
        StrategySettings memory _strategySettings
    )
        MasterChefVariableRewardsStrategy(
            _name,
            _depositToken,
            _ecosystemToken,
            _poolRewardToken,
            _swapPairToken,
            _extraRewards,
            _stakingContract,
            _timelock,
            _pid,
            _strategySettings
        )
    {
        assignSwapPairSafely(_swapPairToken);
    }

    function assignSwapPairSafely(address _swapPairToken) private {
        require(
            DexLibrary.checkSwapPairCompatibility(IPair(_swapPairToken), address(depositToken), address(rewardToken)),
            "swap token does not match deposit and reward token"
        );
        swapPairToken = _swapPairToken;
    }

    function _convertRewardTokenToDepositToken(uint256 fromAmount) internal override returns (uint256 toAmount) {
        toAmount = DexLibrary.swap(fromAmount, address(rewardToken), address(depositToken), IPair(swapPairToken));
    }
}
