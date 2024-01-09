// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./../../BaseStrategy.sol";

import "./interfaces/IMasterChef.sol";
import "./../../../interfaces/IPair.sol";

contract MoeStrategy is BaseStrategy {
    using SafeERC20 for IERC20;

    IMasterChef public immutable masterchef;
    uint256 public immutable pid;

    address internal immutable MOE;
    address internal immutable token0;
    address internal immutable token1;

    constructor(
        address _masterchef,
        uint256 _pid,
        BaseStrategySettings memory _baseStrategySettings,
        StrategySettings memory _strategySettings
    ) BaseStrategy(_baseStrategySettings, _strategySettings) {
        masterchef = IMasterChef(_masterchef);
        pid = _pid;
        MOE = masterchef.getMoe();
        token0 = IPair(address(depositToken)).token0();
        token1 = IPair(address(depositToken)).token1();
    }

    function _depositToStakingContract(uint256 _amount, uint256) internal override {
        IERC20(depositToken).approve(address(masterchef), _amount);
        masterchef.deposit(pid, _amount);
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 withdrawAmount) {
        masterchef.withdraw(pid, _amount);
        return _amount;
    }

    function _pendingRewards() internal view virtual override returns (Reward[] memory) {
        uint256[] memory pids = new uint[](1);
        pids[0] = pid;
        (uint256[] memory moeRewards, address[] memory extraTokens, uint256[] memory extraRewards) =
            masterchef.getPendingRewards(address(this), pids);
        Reward[] memory rewards = new Reward[](extraTokens.length + 1);
        rewards[0] = Reward({reward: MOE, amount: moeRewards[0]});
        for (uint256 i = 0; i < extraTokens.length; i++) {
            rewards[i + 1] = Reward({reward: extraTokens[i], amount: extraRewards[i]});
        }
        return rewards;
    }

    function _getRewards() internal virtual override {
        masterchef.deposit(pid, 0);
    }

    function _convertRewardTokenToDepositToken(uint256 fromAmount) internal override returns (uint256 toAmount) {
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
        IERC20(token0).safeTransfer(depositToken, maxAmountIn0);
        IERC20(token1).safeTransfer(depositToken, amountIn1);

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
        return masterchef.getDeposit(pid, address(this));
    }

    function _emergencyWithdraw() internal override {
        masterchef.emergencyWithdraw(pid);
    }
}
