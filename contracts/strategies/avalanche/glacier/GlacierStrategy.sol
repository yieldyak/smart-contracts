// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./../../VariableRewardsStrategy.sol";

import "./interfaces/IGauge.sol";
import "./interfaces/IRouter.sol";
import "./interfaces/IGlacierBoosterFeeCollector.sol";

contract GlacierStrategy is VariableRewardsStrategy {
    using SafeERC20 for IERC20;

    struct GlacierStrategySettings {
        address gauge;
        address router;
        address swapPairToken0;
        uint256 swapFeeToken0;
        address swapPairToken1;
        uint256 swapFeeToken1;
        address boosterFeeCollector;
    }

    address internal constant GLCR = 0x3712871408a829C5cd4e86DA1f4CE727eFCD28F6;

    address internal immutable token0;
    address internal immutable token1;
    uint256 internal immutable token0Decimals;
    uint256 internal immutable token1Decimals;
    bool internal immutable stablePair;

    IGauge public immutable gauge;
    IRouter public immutable router;

    IGlacierBoosterFeeCollector public boosterFeeCollector;
    address public swapPairToken0;
    address public swapPairToken1;
    uint256 public swapFeeToken0;
    uint256 public swapFeeToken1;

    constructor(
        GlacierStrategySettings memory _glacierStrategySettings,
        VariableRewardsStrategySettings memory _variableRewardsStrategySettings,
        StrategySettings memory _strategySettings
    ) VariableRewardsStrategy(_variableRewardsStrategySettings, _strategySettings) {
        gauge = IGauge(_glacierStrategySettings.gauge);
        router = IRouter(_glacierStrategySettings.router);
        swapPairToken0 = _glacierStrategySettings.swapPairToken0;
        swapPairToken1 = _glacierStrategySettings.swapPairToken1;
        swapFeeToken0 = _glacierStrategySettings.swapFeeToken0;
        swapFeeToken1 = _glacierStrategySettings.swapFeeToken1;
        boosterFeeCollector = IGlacierBoosterFeeCollector(_glacierStrategySettings.boosterFeeCollector);
        token0 = IPair(address(depositToken)).token0();
        token1 = IPair(address(depositToken)).token1();
        token0Decimals = 10 ** IERC20(token0).decimals();
        token1Decimals = 10 ** IERC20(token1).decimals();
        stablePair = IPair(address(depositToken)).stable();
    }

    function updateBoosterFeeCollector(address _collector) external onlyDev {
        boosterFeeCollector = IGlacierBoosterFeeCollector(_collector);
    }

    function updateSwapPairs(
        address _swapPairToken0,
        address _swapPairToken1,
        uint256 _swapFeeToken0,
        uint256 _swapFeeToken1
    ) external onlyDev {
        if (_swapPairToken0 > address(0)) {
            swapPairToken0 = _swapPairToken0;
            swapFeeToken0 = _swapFeeToken0;
        }
        if (_swapPairToken1 > address(0)) {
            swapPairToken1 = _swapPairToken1;
            swapFeeToken1 = _swapFeeToken1;
        }
    }

    function _depositToStakingContract(uint256 _amount, uint256) internal override {
        IERC20(depositToken).approve(address(gauge), _amount);
        gauge.deposit(_amount, 0);
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 withdrawAmount) {
        gauge.withdraw(_amount);
        return _amount;
    }

    function _pendingRewards() internal view virtual override returns (Reward[] memory) {
        uint256 count = supportedRewards.length;
        Reward[] memory rewards = new Reward[](count);
        for (uint256 i = 0; i < count; i++) {
            address token = supportedRewards[i];
            uint256 amount = gauge.earned(token, address(this));
            if (token == GLCR && address(boosterFeeCollector) > address(0)) {
                (uint256 boostFee,) = boosterFeeCollector.calculateBoostFee(address(this), amount);
                amount -= boostFee;
            }
            rewards[i] = Reward({reward: token, amount: amount});
        }
        return rewards;
    }

    function _getRewards() internal virtual override {
        gauge.getReward(address(this), supportedRewards);
        if (address(boosterFeeCollector) > address(0)) {
            uint256 balance = IERC20(GLCR).balanceOf(address(this));
            (uint256 boostFee, address receiver) = boosterFeeCollector.calculateBoostFee(address(this), balance);
            if (boostFee > 0) {
                IERC20(GLCR).safeTransfer(address(receiver), boostFee);
            }
        }
    }

    function _convertRewardTokenToDepositToken(uint256 fromAmount) internal override returns (uint256 toAmount) {
        if (stablePair) {
            uint256 amountIn = fromAmount / 2;
            uint256 token0Out = DexLibrary.estimateConversionThroughPair(
                amountIn, address(rewardToken), token0, IPair(swapPairToken0), swapFeeToken0
            );
            uint256 token1Out = DexLibrary.estimateConversionThroughPair(
                amountIn, address(rewardToken), token1, IPair(swapPairToken1), swapFeeToken1
            );
            (uint256 quote0, uint256 quote1,) =
                IRouter(router).quoteAddLiquidity(token0, token1, true, token0Out, token1Out);
            quote0 = quote0 * 1e18 / token0Decimals;
            quote1 = quote1 * 1e18 / token1Decimals;
            uint256 ratio = token0Out * 1e18 / token1Out * quote1 / quote0;
            uint256 token0In = fromAmount * 1e18 / (ratio + 1e18);
            uint256 token1In = fromAmount - token0In;

            uint256 amountOutToken0 =
                DexLibrary.swap(token0In, address(rewardToken), token0, IPair(swapPairToken0), swapFeeToken0);
            uint256 amountOutToken1 =
                DexLibrary.swap(token1In, address(rewardToken), token1, IPair(swapPairToken1), swapFeeToken1);

            toAmount = DexLibrary.addLiquidity(address(depositToken), amountOutToken0, amountOutToken1);
        } else {
            toAmount = DexLibrary.convertRewardTokensToDepositTokens(
                fromAmount,
                address(rewardToken),
                address(depositToken),
                IPair(swapPairToken0),
                swapFeeToken0,
                IPair(swapPairToken1),
                swapFeeToken1
            );
        }
    }

    function totalDeposits() public view override returns (uint256) {
        return gauge.balanceOf(address(this));
    }

    function _emergencyWithdraw() internal override {
        gauge.withdrawAll();
    }
}
