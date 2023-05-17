// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../interfaces/IPair.sol";
import "../lib/DexLibrary.sol";
import "./VariableRewardsStrategy.sol";

/**
 * @notice Adapter strategy for VariableRewardsStrategy with SA deposit.
 */
abstract contract VariableRewardsStrategyForSAV2 is VariableRewardsStrategy {
    address public immutable swapPairDepositToken;
    uint256 public immutable swapFeeBips;

    constructor(
        address _swapPairDepositToken,
        uint256 _swapFeeBips,
        VariableRewardsStrategySettings memory _settings,
        StrategySettings memory _strategySettings
    ) VariableRewardsStrategy(_settings, _strategySettings) {
        swapPairDepositToken = _swapPairDepositToken;
        assignSwapPairSafely(_swapPairDepositToken);
        swapFeeBips = _swapFeeBips;
    }

    function assignSwapPairSafely(address _swapPairDepositToken) internal virtual {
        if (address(rewardToken) != address(depositToken)) {
            require(
                DexLibrary.checkSwapPairCompatibility(
                    IPair(_swapPairDepositToken), address(depositToken), address(rewardToken)
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
        return DexLibrary.swap(
            fromAmount, address(rewardToken), address(depositToken), IPair(swapPairDepositToken), swapFeeBips
        );
    }
}
