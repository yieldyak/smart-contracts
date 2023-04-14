// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./../../VariableRewardsStrategy.sol";
import "./interfaces/IFlairVoterProxy.sol";

contract FlairStrategy is VariableRewardsStrategy {
    using SafeERC20 for IERC20;

    address private constant USDT = 0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7;
    address private constant USDC = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E;

    struct FlairStrategySettings {
        address gauge;
        address swapPairToken0;
        bool swapPairToken0IsSolidlyStablePair;
        uint256 swapFeeToken0;
        address swapPairToken1;
        bool swapPairToken1IsSolidlyStablePair;
        uint256 swapFeeToken1;
        address voterProxy;
        bool claimBribes;
    }

    address internal constant FLDX = 0x107D2b7C619202D994a4d044c762Dd6F8e0c5326;

    address public immutable gauge;

    IFlairVoterProxy public voterProxy;
    address public swapPairToken0;
    address public swapPairToken1;
    uint256 public swapFeeToken0;
    uint256 public swapFeeToken1;
    bool public swapPairToken0IsStable;
    bool public swapPairToken1IsStable;
    bool public claimBribes;

    address internal immutable token0;
    address internal immutable token1;

    constructor(
        FlairStrategySettings memory _flairStrategySettings,
        VariableRewardsStrategySettings memory _variableRewardsStrategySettings,
        StrategySettings memory _strategySettings
    ) VariableRewardsStrategy(_variableRewardsStrategySettings, _strategySettings) {
        gauge = _flairStrategySettings.gauge;
        swapPairToken0 = _flairStrategySettings.swapPairToken0;
        swapPairToken1 = _flairStrategySettings.swapPairToken1;
        swapFeeToken0 = _flairStrategySettings.swapFeeToken0;
        swapFeeToken1 = _flairStrategySettings.swapFeeToken1;
        swapPairToken0IsStable = _flairStrategySettings.swapPairToken0IsSolidlyStablePair;
        swapPairToken1IsStable = _flairStrategySettings.swapPairToken1IsSolidlyStablePair;
        voterProxy = IFlairVoterProxy(_flairStrategySettings.voterProxy);
        token0 = IPair(address(depositToken)).token0();
        token1 = IPair(address(depositToken)).token1();
        claimBribes = _flairStrategySettings.claimBribes;
    }

    function updateVoterProxy(address _proxy) external onlyDev {
        voterProxy = IFlairVoterProxy(_proxy);
    }

    function updateClaimBribes(bool _newValue) external onlyDev {
        claimBribes = _newValue;
    }

    function updateSwapPairs(
        address _swapPairToken0,
        address _swapPairToken1,
        uint256 _swapFeeToken0,
        uint256 _swapFeeToken1,
        bool _swapPairToken0IsSolidlyStablePair,
        bool _swapPairToken1IsSolidlyStablePair
    ) external onlyDev {
        if (_swapPairToken0 > address(0)) {
            swapPairToken0 = _swapPairToken0;
            swapFeeToken0 = _swapFeeToken0;
            swapPairToken0IsStable = _swapPairToken0IsSolidlyStablePair;
        }
        if (_swapPairToken1 > address(0)) {
            swapPairToken1 = _swapPairToken1;
            swapFeeToken1 = _swapFeeToken1;
            swapPairToken1IsStable = _swapPairToken1IsSolidlyStablePair;
        }
    }

    function _depositToStakingContract(uint256 _amount, uint256) internal override {
        depositToken.safeTransfer(address(voterProxy.voter()), _amount);
        voterProxy.deposit(gauge, address(depositToken), _amount);
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 withdrawAmount) {
        voterProxy.withdraw(gauge, address(depositToken), _amount);
        return _amount;
    }

    function _pendingRewards() internal view virtual override returns (Reward[] memory) {
        return voterProxy.pendingRewards(gauge, supportedRewards, claimBribes);
    }

    function _getRewards() internal virtual override {
        voterProxy.getRewards(gauge, supportedRewards, claimBribes);
    }

    function _convertRewardTokenToDepositToken(uint256 fromAmount) internal override returns (uint256 toAmount) {
        uint256 amountIn = fromAmount / 2;
        require(amountIn > 0, "FlairStrategy::convertRewardTokensToDepositTokens");

        uint256 amountOutToken0 = amountIn;
        if (address(rewardToken) != token0) {
            _swap(amountIn, address(rewardToken), token0, swapPairToken0, swapFeeToken0, swapPairToken0IsStable);
        }

        uint256 amountOutToken1 = amountIn;
        if (address(rewardToken) != token1) {
            _swap(amountIn, address(rewardToken), token1, swapPairToken1, swapFeeToken1, swapPairToken1IsStable);
        }

        amountOutToken0 = IERC20(token0).balanceOf(address(this));
        amountOutToken1 = IERC20(token1).balanceOf(address(this));

        return DexLibrary.addLiquidity(address(depositToken), amountOutToken0, amountOutToken1);
    }

    function _swap(
        uint256 _amountIn,
        address _fromToken,
        address _toToken,
        address _pair,
        uint256 _swapFee,
        bool _stablePair
    ) internal returns (uint256) {
        if (_stablePair) {
            uint256 amountOut = IPair(_pair).getAmountOut(_amountIn, _fromToken);
            (uint256 amount0Out, uint256 amount1Out) =
                (_fromToken < _toToken) ? (uint256(0), amountOut) : (amountOut, uint256(0));
            IERC20(_fromToken).safeTransfer(address(_pair), _amountIn);
            IPair(_pair).swap(amount0Out, amount1Out, address(this), new bytes(0));
            return amount0Out > amount1Out ? amount0Out : amount1Out;
        }
        return DexLibrary.swap(_amountIn, _fromToken, _toToken, IPair(_pair), _swapFee);
    }

    function totalDeposits() public view override returns (uint256) {
        return voterProxy.totalDeposits(gauge);
    }

    function _emergencyWithdraw() internal override {
        voterProxy.emergencyWithdraw(gauge, address(depositToken));
    }
}
