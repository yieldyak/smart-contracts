// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./PlatypusStrategy.sol";

contract YYAvaxPlatypusStrategy is PlatypusStrategy {
    address public constant yyAVAX = 0xF7D9281e8e363584973F946201b82ba72C965D27;

    constructor(
        PlatypusStrategySettings memory _platypusStrategySettings,
        VariableRewardsStrategySettings memory _variableRewardsStrategySettings,
        StrategySettings memory _strategySettings
    ) PlatypusStrategy(_platypusStrategySettings, _variableRewardsStrategySettings, _strategySettings) {}

    function _pendingRewards() internal view override returns (Reward[] memory) {
        Reward[] memory rewards = proxy.pendingRewards(PID);
        for (uint256 i = 0; i < rewards.length; i++) {
            if (rewards[i].reward == yyAVAX) {
                (rewards[i].amount,) = pool.quotePotentialSwap(yyAVAX, address(WGAS), rewards[i].amount);
                rewards[i].reward = address(WGAS);
            }
        }
        return rewards;
    }

    function _getRewards() internal override {
        super._getRewards();
        uint256 yyAvaxBalance = IERC20(yyAVAX).balanceOf(address(this));
        if (yyAvaxBalance > 0) {
            IERC20(yyAVAX).approve(address(pool), yyAvaxBalance);
            pool.swap(yyAVAX, address(WGAS), yyAvaxBalance, 0, address(this), type(uint256).max);
            IERC20(yyAVAX).approve(address(pool), 0);
        }
    }

    function _convertRewardTokenToDepositToken(uint256 _fromAmount) internal override returns (uint256 toAmount) {
        if (address(depositToken) == yyAVAX) {
            WGAS.approve(address(pool), _fromAmount);
            (toAmount,) = pool.swap(address(WGAS), yyAVAX, _fromAmount, 0, address(this), type(uint256).max);
            WGAS.approve(address(pool), 0);
        } else {
            return super._convertRewardTokenToDepositToken(_fromAmount);
        }
    }
}
