// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./../../BaseStrategy.sol";

import "./interfaces/IGauge.sol";
import "./interfaces/IRouter.sol";
import "./interfaces/IAerodromPair.sol";
import "./../../../interfaces/IPair.sol";

contract AerodromeStrategy is BaseStrategy {
    using SafeERC20 for IERC20;

    address internal immutable token0;
    address internal immutable token1;
    uint256 internal immutable token0Decimals;
    uint256 internal immutable token1Decimals;
    bool internal immutable stablePair;

    IGauge public immutable gauge;
    IRouter public immutable router;
    address public immutable gaugeReward;
    address public immutable factory;

    constructor(
        address _gauge,
        address _router,
        BaseStrategySettings memory _baseStrategySettings,
        StrategySettings memory _strategySettings
    ) BaseStrategy(_baseStrategySettings, _strategySettings) {
        require(rewardToken.decimals() == 18, "AerodromeStrategy::Assumes reward token with 18 decimals");
        gauge = IGauge(_gauge);
        router = IRouter(_router);
        factory = IAerodromPair(address(depositToken)).factory();
        gaugeReward = gauge.rewardToken();
        token0 = IPair(address(depositToken)).token0();
        token1 = IPair(address(depositToken)).token1();
        token0Decimals = 10 ** IERC20(token0).decimals();
        token1Decimals = 10 ** IERC20(token1).decimals();
        stablePair = IPair(address(depositToken)).stable();
    }

    function _depositToStakingContract(uint256 _amount, uint256) internal override {
        IERC20(depositToken).approve(address(gauge), _amount);
        gauge.deposit(_amount);
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 withdrawAmount) {
        gauge.withdraw(_amount);
        return _amount;
    }

    function _pendingRewards() internal view virtual override returns (Reward[] memory) {
        uint256 count = supportedRewards.length;
        Reward[] memory rewards = new Reward[](count);
        uint256 amount = gauge.earned(address(this));
        rewards[0] = Reward({reward: gaugeReward, amount: amount});
        return rewards;
    }

    function _getRewards() internal virtual override {
        gauge.getReward(address(this));
    }

    function _convertRewardTokenToDepositToken(uint256 fromAmount) internal override returns (uint256 toAmount) {
        if (stablePair) {
            uint256 amountIn = fromAmount / 2;

            uint256 token0Out = amountIn;
            if (token0 != address(rewardToken)) {
                FormattedOffer memory offer = simpleRouter.query(amountIn, address(rewardToken), token0);
                token0Out = offer.amounts[offer.amounts.length - 1];
            }

            uint256 token1Out = amountIn;
            if (token1 != address(rewardToken)) {
                FormattedOffer memory offer = simpleRouter.query(amountIn, address(rewardToken), token1);
                token1Out = offer.amounts[offer.amounts.length - 1];
            }

            (uint256 quote0, uint256 quote1,) =
                IRouter(router).quoteAddLiquidity(token0, token1, true, factory, token0Out, token1Out);
            token0Out = token0Out * 1e18 / token0Decimals;
            token1Out = token1Out * 1e18 / token1Decimals;
            quote0 = quote0 * 1e18 / token0Decimals;
            quote1 = quote1 * 1e18 / token1Decimals;
            uint256 ratio = token0Out * 1e18 / token1Out * quote1 / quote0;
            uint256 token0In = fromAmount * 1e18 / (ratio + 1e18);
            uint256 token1In = fromAmount - token0In;

            token0Out = token0In;
            if (token0 != address(rewardToken)) {
                FormattedOffer memory offer = simpleRouter.query(token0In, address(rewardToken), token0);
                rewardToken.approve(address(simpleRouter), token0In);
                token0Out = simpleRouter.swap(offer);
            }

            token1Out = token1In;
            if (token1 != address(rewardToken)) {
                FormattedOffer memory offer = simpleRouter.query(token1In, address(rewardToken), token1);
                rewardToken.approve(address(simpleRouter), token1In);
                token1Out = simpleRouter.swap(offer);
            }

            IERC20(token0).approve(address(router), token0Out);
            IERC20(token1).approve(address(router), token1Out);
            (,, toAmount) =
                router.addLiquidity(token0, token1, true, token0Out, token1Out, 0, 0, address(this), block.timestamp);
        } else {
            fromAmount = fromAmount / 2;
            if (address(rewardToken) != token0) {
                FormattedOffer memory offer = simpleRouter.query(fromAmount, address(rewardToken), token0);
                rewardToken.approve(address(simpleRouter), fromAmount);
                simpleRouter.swap(offer);
            }
            if (address(rewardToken) != token1) {
                FormattedOffer memory offer = simpleRouter.query(fromAmount, address(rewardToken), token1);
                rewardToken.approve(address(simpleRouter), fromAmount);
                simpleRouter.swap(offer);
            }
            toAmount = addLiquidity(
                address(depositToken), IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this))
            );
        }
    }

    function addLiquidity(address depositToken, uint256 maxAmountIn0, uint256 maxAmountIn1)
        internal
        returns (uint256)
    {
        (uint112 reserve0, uint112 reserve1,) = IPair(address(depositToken)).getReserves();
        uint256 amountIn1 = _quoteLiquidityAmountOut(maxAmountIn0, reserve0, reserve1);
        if (amountIn1 > maxAmountIn1) {
            amountIn1 = maxAmountIn1;
            maxAmountIn0 = _quoteLiquidityAmountOut(maxAmountIn1, reserve1, reserve0);
        }
        IERC20(IPair(depositToken).token0()).safeTransfer(depositToken, maxAmountIn0);
        IERC20(IPair(depositToken).token1()).safeTransfer(depositToken, amountIn1);

        return IPair(depositToken).mint(address(this));
    }

    function _quoteLiquidityAmountOut(uint256 amountIn, uint256 reserve0, uint256 reserve1)
        private
        pure
        returns (uint256)
    {
        return (amountIn * reserve1) / reserve0;
    }

    function totalDeposits() public view override returns (uint256) {
        return gauge.balanceOf(address(this));
    }

    function _emergencyWithdraw() internal override {
        gauge.withdrawAll();
    }
}
