// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../interfaces/IPair.sol";
import "../lib/DexLibrary.sol";
import "./VariableRewardsStrategy.sol";

/**
 * @notice Adapter strategy for VariableRewardsStrategy with SA deposit.
 */
abstract contract VariableRewardsStrategyForSA is VariableRewardsStrategy {
    address private swapPairDepositToken;

    constructor(
        address _swapPairDepositToken,
        RewardSwapPairs[] memory _rewardSwapPairs,
        BaseSettings memory _baseSettings,
        StrategySettings memory _strategySettings
    ) VariableRewardsStrategy(_rewardSwapPairs, _baseSettings, _strategySettings) {
        assignSwapPairSafely(_swapPairDepositToken);
    }

    function assignSwapPairSafely(address _swapPairDepositToken) private {
        require(
            DexLibrary.checkSwapPairCompatibility(
                IPair(_swapPairDepositToken),
                address(depositToken),
                address(rewardToken)
            ),
            "VariableRewardsStrategyForSA::swapPairDepositToken does not match deposit and reward token"
        );
        swapPairDepositToken = _swapPairDepositToken;
    }

    function _convertRewardTokenToDepositToken(uint256 fromAmount)
        internal
        virtual
        override
        returns (uint256 toAmount)
    {
        toAmount = DexLibrary.swap(
            fromAmount,
            address(rewardToken),
            address(depositToken),
            IPair(swapPairDepositToken)
        );
    }
}
