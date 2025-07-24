// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./../../BaseStrategy.sol";

import "./../../../interfaces/IPair.sol";
import "./interfaces/IGauge.sol";
import "./interfaces/IRouter.sol";

contract BlackholeStableStrategy is BaseStrategy {
    using SafeERC20 for IERC20;

    IGauge public immutable gauge;
    IRouter public immutable router;

    address internal immutable token0;
    address internal immutable token1;

    constructor(
        address _gauge,
        address _router,
        BaseStrategySettings memory _variableRewardsStrategySettings,
        StrategySettings memory _strategySettings
    ) BaseStrategy(_variableRewardsStrategySettings, _strategySettings) {
        require(IPair(address(depositToken)).stable(), "BlackholeStable::Only stable pairs supported");
        gauge = IGauge(_gauge);
        router = IRouter(_router);
        token0 = IPair(address(depositToken)).token0();
        token1 = IPair(address(depositToken)).token1();
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
        for (uint256 i = 0; i < count; i++) {
            address token = supportedRewards[i];
            uint256 amount = gauge.earned(address(this));
            rewards[i] = Reward({reward: token, amount: amount});
        }
        return rewards;
    }

    function _getRewards() internal virtual override {
        gauge.getReward();
    }

    function _convertRewardTokenToDepositToken(uint256 fromAmount) internal override returns (uint256 toAmount) {
        return _convertForStablePool(fromAmount);
    }

    function _convertForStablePool(uint256 fromAmount) internal returns (uint256 toAmount) {
        // Test conversion to determine optimal ratio
        uint256 testAmount = fromAmount / 2;
        
        uint256 token0TestOut = testAmount;
        if (token0 != address(rewardToken)) {
            FormattedOffer memory offer = simpleRouter.query(testAmount, address(rewardToken), token0);
            token0TestOut = offer.amounts[offer.amounts.length - 1];
        }

        uint256 token1TestOut = testAmount;
        if (token1 != address(rewardToken)) {
            FormattedOffer memory offer = simpleRouter.query(testAmount, address(rewardToken), token1);
            token1TestOut = offer.amounts[offer.amounts.length - 1];
        }

        // Get quotes from stable pool for optimal ratio
        (uint256 quote0, uint256 quote1,) = router.quoteAddLiquidity(
            token0, 
            token1, 
            true,
            token0TestOut, 
            token1TestOut
        );

        // Calculate optimal split based on stable curve requirements
        uint256 ratio = token0TestOut * 1e18 / token1TestOut * quote1 / quote0;
        uint256 token0In = fromAmount * 1e18 / (ratio + 1e18);
        uint256 token1In = fromAmount - token0In;

        // Perform swaps
        uint256 token0Out = token0In;
        if (token0 != address(rewardToken)) {
            FormattedOffer memory offer = simpleRouter.query(token0In, address(rewardToken), token0);
            rewardToken.approve(address(simpleRouter), token0In);
            token0Out = simpleRouter.swap(offer);
        }

        uint256 token1Out = token1In;
        if (token1 != address(rewardToken)) {
            FormattedOffer memory offer = simpleRouter.query(token1In, address(rewardToken), token1);
            rewardToken.approve(address(simpleRouter), token1In);
            token1Out = simpleRouter.swap(offer);
        }

        return _addLiquidityPrecise(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)));
    }

    function _addLiquidityPrecise(uint256 token0Available, uint256 token1Available) internal returns (uint256) {
        (uint256 token0Amount, uint256 token1Amount,) = router.quoteAddLiquidity(
            token0,
            token1,
            true,
            token0Available,
            token1Available
        );
        
        IERC20(token0).safeTransfer(address(depositToken), token0Amount);
        IERC20(token1).safeTransfer(address(depositToken), token1Amount);
        
        return IPair(address(depositToken)).mint(address(this));
    }

    function totalDeposits() public view override returns (uint256) {
        return gauge.balanceOf(address(this));
    }

    function _emergencyWithdraw() internal override {
        gauge.withdrawAll();
    }
}
