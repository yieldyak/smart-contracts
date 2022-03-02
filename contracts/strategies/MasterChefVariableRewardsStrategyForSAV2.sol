// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "../interfaces/IPair.sol";
import "../lib/DexLibrary.sol";
import "./MasterChefVariableRewardsStrategyV2.sol";

/**
 * @notice Adapter strategy for MasterChef with SA deposit.
 */
abstract contract MasterChefVariableRewardsStrategyForSAV2 is MasterChefVariableRewardsStrategyV2 {
    address private swapPairDepositToken;

    constructor(
        string memory _name,
        address _depositToken,
        address _swapPairDepositToken,
        RewardSwapPairs[] memory _rewardSwapPairs,
        address _timelock,
        uint256 _pid,
        StrategySettings memory _strategySettings
    ) MasterChefVariableRewardsStrategyV2(_name, _depositToken, _rewardSwapPairs, _timelock, _pid, _strategySettings) {
        assignSwapPairSafely(_swapPairDepositToken);
    }

    function assignSwapPairSafely(address _swapPairDepositToken) private {
        require(
            DexLibrary.checkSwapPairCompatibility(
                IPair(_swapPairDepositToken),
                address(depositToken),
                address(rewardToken)
            ),
            "MasterChefVariableRewardsStrategyForSAV2::swapPairDepositToken does not match deposit and reward token"
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
