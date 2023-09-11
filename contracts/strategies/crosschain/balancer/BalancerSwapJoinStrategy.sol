// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./BalancerStrategy.sol";

contract BalancerSwapJoinStrategy is BalancerStrategy {
    struct SwapStep {
        bytes32 poolId;
        uint256 assetInIndex;
        uint256 assetOutIndex;
    }

    SwapStep[] public route;
    address[] public routeAssets;

    constructor(
        SwapStep[] memory _route,
        BalancerStrategySettings memory _balancerStrategySettings,
        BaseStrategySettings memory _settings,
        StrategySettings memory _strategySettings
    ) BalancerStrategy(_balancerStrategySettings, _settings, _strategySettings) {
        for (uint256 i; i < _route.length; i++) {
            SwapStep storage step = route.push();
            step.poolId = _route[i].poolId;
            step.assetInIndex = _route[i].assetInIndex;
            step.assetOutIndex = _route[i].assetOutIndex;
        }
        routeAssets = new address[](_route.length + 1);
        routeAssets[0] = balancerPoolTokenIn;
        for (uint256 i; i < _route.length; i++) {
            (address pool,) = balancerVault.getPool(_route[i].poolId);
            routeAssets[i + 1] = pool;
        }
    }

    function _joinPool(uint256 _amountIn) internal override returns (uint256 amountOut) {
        uint256 length = route.length;
        IBalancerVault.BatchSwapStep[] memory swaps = new IBalancerVault.BatchSwapStep[](length);
        for (uint256 i; i < length; i++) {
            swaps[i] = IBalancerVault.BatchSwapStep({
                poolId: route[i].poolId,
                assetInIndex: route[i].assetInIndex,
                assetOutIndex: route[i].assetOutIndex,
                amount: i == 0 ? _amountIn : 0,
                userData: ""
            });
        }
        int256[] memory limits = new int256[](length + 1);
        limits[0] = int256(_amountIn);

        IBalancerVault.FundManagement memory fundManagement = IBalancerVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });

        IERC20(balancerPoolTokenIn).approve(address(balancerVault), _amountIn);
        balancerVault.batchSwap(
            IBalancerVault.SwapKind.GIVEN_IN, swaps, routeAssets, fundManagement, limits, type(uint256).max
        );

        return depositToken.balanceOf(address(this));
    }
}
