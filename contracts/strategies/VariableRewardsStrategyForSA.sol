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
        VariableRewardsStrategySettings memory _settings,
        StrategySettings memory _strategySettings
    ) VariableRewardsStrategy(_settings, _strategySettings) {
        assignSwapPairSafely(_swapPairDepositToken);
    }

    function assignSwapPairSafely(address _swapPairDepositToken) internal virtual {
        if (address(rewardToken) != address(depositToken)) {
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
    }

    function _convertRewardTokenToDepositToken(uint256 fromAmount)
        internal
        virtual
        override
        returns (uint256 toAmount)
    {
        if (address(rewardToken) == address(depositToken)) {
            return fromAmount;
        }
        return DexLibrary.swap(fromAmount, address(rewardToken), address(depositToken), IPair(swapPairDepositToken));
    }
}
