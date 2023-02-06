// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./PlatypusStrategy.sol";

contract AnkrAvaxPlatypusStrategy is PlatypusStrategy {
    address public constant ankrAVAX = 0xc3344870d52688874b06d844E0C36cc39FC727F6;

    constructor(
        PlatypusStrategySettings memory _platypusStrategySettings,
        VariableRewardsStrategySettings memory _variableRewardsStrategySettings,
        StrategySettings memory _strategySettings
    ) PlatypusStrategy(_platypusStrategySettings, _variableRewardsStrategySettings, _strategySettings) {}

    function _pendingRewards() internal view override returns (Reward[] memory) {
        Reward[] memory rewards = proxy.pendingRewards(PID);
        for (uint256 i = 0; i < rewards.length; i++) {
            if (rewards[i].reward == ankrAVAX) {
                (rewards[i].amount, ) = pool.quotePotentialSwap(ankrAVAX, address(WAVAX), rewards[i].amount);
                rewards[i].reward = address(WAVAX);
            }
        }
        return rewards;
    }

    function _getRewards() internal override {
        super._getRewards();
        uint256 ankrAVAXBalance = IERC20(ankrAVAX).balanceOf(address(this));
        if (ankrAVAXBalance > 0) {
            IERC20(ankrAVAX).approve(address(pool), ankrAVAXBalance);
            pool.swap(ankrAVAX, address(WAVAX), ankrAVAXBalance, 0, address(this), type(uint256).max);
            IERC20(ankrAVAX).approve(address(pool), 0);
        }
    }

    function _convertRewardTokenToDepositToken(uint256 _fromAmount) internal override returns (uint256 toAmount) {
        if (address(depositToken) == ankrAVAX) {
            WAVAX.approve(address(pool), _fromAmount);
            (toAmount, ) = pool.swap(address(WAVAX), ankrAVAX, _fromAmount, 0, address(this), type(uint256).max);
            WAVAX.approve(address(pool), 0);
        } else {
            return super._convertRewardTokenToDepositToken(_fromAmount);
        }
    }
}
