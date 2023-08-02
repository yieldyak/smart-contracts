// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./PlatypusStrategy.sol";

contract UspPlatypusStrategy is PlatypusStrategy {
    address public constant USP = 0xdaCDe03d7Ab4D81fEDdc3a20fAA89aBAc9072CE2;
    IERC20 public constant USDC = IERC20(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E);

    constructor(
        PlatypusStrategySettings memory _platypusStrategySettings,
        VariableRewardsStrategySettings memory _variableRewardsStrategySettings,
        StrategySettings memory _strategySettings
    ) PlatypusStrategy(_platypusStrategySettings, _variableRewardsStrategySettings, _strategySettings) {}

    function _convertRewardTokenToDepositToken(uint256 _fromAmount) internal override returns (uint256 toAmount) {
        // swap WGAS to USDC
        WGAS.approve(address(swapPairToken), _fromAmount);
        uint256 usdcAmount = DexLibrary.swap(_fromAmount, address(WGAS), address(USDC), IPair(swapPairToken));
        WGAS.approve(address(swapPairToken), 0);

        // swap USDC to USP
        USDC.approve(address(pool), usdcAmount);
        (toAmount,) = pool.swap(address(USDC), USP, usdcAmount, 0, address(this), type(uint256).max);
        USDC.approve(address(pool), 0);
    }
}
