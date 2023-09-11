// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./BalancerStrategy.sol";

contract BalancerDirectJoinStrategy is BalancerStrategy {
    uint256 constant JOIN_KIND = 1; // EXACT_TOKENS_IN_FOR_BPT_OUT
    uint256 immutable bptIndex;
    bool public immutable dropBptAmountOnPoolJoin;

    constructor(
        bool _dropBptAmountOnPoolJoin,
        BalancerStrategySettings memory _balancerStrategySettings,
        BaseStrategySettings memory _settings,
        StrategySettings memory _strategySettings
    ) BalancerStrategy(_balancerStrategySettings, _settings, _strategySettings) {
        dropBptAmountOnPoolJoin = _dropBptAmountOnPoolJoin;
        bptIndex = IBalancerPool(address(depositToken)).getBptIndex();
    }

    function _joinPool(uint256 _amountIn) internal override returns (uint256 amountOut) {
        uint256[] memory amounts = new uint256[](poolTokens.length);
        uint256[] memory userDataAmounts = new uint[](dropBptAmountOnPoolJoin ? amounts.length - 1 : amounts.length);
        uint256 userDataAmountsIndex;
        for (uint256 i = 0; i < amounts.length; i++) {
            amounts[i] = poolTokens[i] == balancerPoolTokenIn ? _amountIn : 0;
            if (dropBptAmountOnPoolJoin && i != bptIndex) {
                userDataAmounts[userDataAmountsIndex] = poolTokens[i] == balancerPoolTokenIn ? _amountIn : 0;
                userDataAmountsIndex++;
            }
        }
        bytes memory userData = abi.encode(JOIN_KIND, userDataAmounts, 0);

        IBalancerVault.JoinPoolRequest memory request =
            IBalancerVault.JoinPoolRequest(poolTokens, amounts, userData, false);
        IERC20(balancerPoolTokenIn).approve(address(balancerVault), _amountIn);
        balancerVault.joinPool(poolId, address(this), address(this), request);
        return depositToken.balanceOf(address(this));
    }
}
