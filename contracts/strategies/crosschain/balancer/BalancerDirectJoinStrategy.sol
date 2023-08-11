// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./BalancerStrategy.sol";

contract BalancerDirectJoinStrategy is BalancerStrategy {
    constructor(
        BalancerStrategySettings memory _balancerStrategySettings,
        BaseStrategySettings memory _settings,
        StrategySettings memory _strategySettings
    ) BalancerStrategy(_balancerStrategySettings, _settings, _strategySettings) {}

    function _joinPool(uint256 _amountIn) internal override returns (uint256 amountOut) {
        uint256[] memory amounts = new uint256[](poolTokens.length);
        for (uint256 i = 0; i < amounts.length; i++) {
            amounts[i] = poolTokens[i] == balancerPoolTokenIn ? _amountIn : 0;
        }
        bytes memory userData = abi.encode(1, amounts, 1);

        IBalancerVault.JoinPoolRequest memory request =
            IBalancerVault.JoinPoolRequest(poolTokens, amounts, userData, false);
        IERC20(balancerPoolTokenIn).approve(address(balancerVault), _amountIn);
        balancerVault.joinPool(poolId, address(this), address(this), request);
        return depositToken.balanceOf(address(this));
    }
}
