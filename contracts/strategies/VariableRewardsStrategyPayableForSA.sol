// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../interfaces/IPair.sol";
import "../lib/DexLibrary.sol";
import "./VariableRewardsStrategyPayable.sol";

/**
 * @notice Adapter strategy for VariableRewardsStrategy with SA deposit.
 */
abstract contract VariableRewardsStrategyPayableForSA is VariableRewardsStrategyPayable {
    address private immutable swapPairDepositToken;

    constructor(
        address _swapPairDepositToken,
        VariableRewardsStrategySettings memory _settings,
        StrategySettings memory _strategySettings
    ) VariableRewardsStrategyPayable(_settings, _strategySettings) {
        swapPairDepositToken = _swapPairDepositToken;
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
