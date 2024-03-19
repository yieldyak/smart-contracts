// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./../../BaseStrategy.sol";

import "./../../../interfaces/IPair.sol";
import "./../../../interfaces/ILamaPay.sol";

contract MemeRushStrategy is BaseStrategy {
    using SafeERC20 for IERC20;

    address internal immutable token0;
    address internal immutable token1;

    uint256 public staked;

    ILamaPay public lamaPay;
    address public payer;
    uint216 public amountPerSec;
    bool public streaming;

    constructor(BaseStrategySettings memory _baseStrategySettings, StrategySettings memory _strategySettings)
        BaseStrategy(_baseStrategySettings, _strategySettings)
    {
        token0 = IPair(address(depositToken)).token0();
        token1 = IPair(address(depositToken)).token1();
    }

    function updateLamaPay(address _lamaPay, address _payer, uint216 _amountPerSec) external onlyDev {
        _getRewards();
        lamaPay = ILamaPay(_lamaPay);
        payer = _payer;
        amountPerSec = _amountPerSec;
        streaming = _lamaPay > address(0) && _payer > address(0) && _amountPerSec > 0;
    }

    function _depositToStakingContract(uint256 _amount, uint256) internal override {
        staked += _amount;
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 withdrawAmount) {
        staked -= _amount;
        return _amount;
    }

    function _pendingRewards() internal view virtual override returns (Reward[] memory) {
        if (!streaming) return new Reward[](0);

        (uint256 withdrawableAmount,,) = lamaPay.withdrawable(payer, address(this), amountPerSec);
        Reward[] memory rewards = new Reward[](1);
        rewards[0] = Reward({reward: lamaPay.token(), amount: withdrawableAmount});
        return rewards;
    }

    function _getRewards() internal virtual override {
        if (streaming) {
            lamaPay.withdraw(payer, address(this), amountPerSec);
        }
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
        return staked;
    }

    function _emergencyWithdraw() internal override {}
}
