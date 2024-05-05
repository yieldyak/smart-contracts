// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./../lamapay/LamaPayStrategyBase.sol";

import "./interfaces/IPendleProxy.sol";
import "./interfaces/IPendleRouter.sol";
import "./interfaces/IPendleMarketLP.sol";
import "./interfaces/ISy.sol";

contract BoostedPendleStrategy is LamaPayStrategyBase {
    using SafeERC20 for IERC20;

    IPendleProxy public proxy;

    address public immutable lpTokenIn;
    IPendleRouter public immutable pendleRouter;

    // EmptySwap means no swap aggregator is involved
    IPendleRouter.SwapData private emptySwap;
    // EmptyLimit means no limit order is involved
    IPendleRouter.LimitOrderData private emptyLimit;
    // DefaultApprox means no off-chain preparation is involved, more gas consuming (~ 180k gas)
    IPendleRouter.ApproxParams private defaultApprox = IPendleRouter.ApproxParams(0, type(uint256).max, 0, 256, 1e14);

    constructor(
        address _proxy,
        address _pendleRouter,
        BaseStrategySettings memory baseStrategySettings,
        StrategySettings memory _strategySettings
    ) LamaPayStrategyBase(baseStrategySettings, _strategySettings) {
        proxy = IPendleProxy(_proxy);
        pendleRouter = IPendleRouter(_pendleRouter);
        (address sy,,) = IPendleMarketLP(address(depositToken)).readTokens();
        lpTokenIn = ISy(sy).yieldToken();
    }

    function setProxy(address _proxy) external onlyDev {
        proxy = IPendleProxy(_proxy);
    }

    function _depositToStakingContract(uint256 _amount, uint256) internal override {
        depositToken.transfer(proxy.voter(), _amount);
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 _withdrawAmount) {
        proxy.withdrawFromStakingContract(address(depositToken), _amount);
        return _amount;
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        Reward[] memory rewardsProxy = proxy.pendingRewards(address(depositToken));

        uint256 length = rewardsProxy.length + streams.length;

        Reward[] memory rewards = new Reward[](length);
        uint256 i;
        for (i; i < streams.length; i++) {
            rewards[i] = _readStream(streams[i]);
        }
        for (uint256 j; j < rewardsProxy.length; j++) {
            rewards[i + j] = rewardsProxy[j];
        }
        return rewards;
    }

    function _getRewards() internal override {
        super._getRewards();
        proxy.getRewards(address(depositToken));
    }

    function _convertRewardTokenToDepositToken(uint256 _fromAmount) internal override returns (uint256 out) {
        if (address(rewardToken) != lpTokenIn) {
            FormattedOffer memory offer = simpleRouter.query(_fromAmount, address(rewardToken), lpTokenIn);
            _fromAmount = _swap(offer);
        }
        if (_fromAmount > 0) {
            IERC20(lpTokenIn).approve(address(pendleRouter), _fromAmount);
            IPendleRouter.TokenInput memory tokenInput = IPendleRouter.TokenInput({
                tokenIn: lpTokenIn,
                netTokenIn: _fromAmount,
                tokenMintSy: lpTokenIn,
                pendleSwap: address(0),
                swapData: emptySwap
            });
            (out,,) = pendleRouter.addLiquiditySingleToken(
                address(this), address(depositToken), 0, defaultApprox, tokenInput, emptyLimit
            );
        }
    }

    function totalDeposits() public view override returns (uint256) {
        return proxy.totalDeposits(address(depositToken));
    }

    function _emergencyWithdraw() internal override {
        proxy.emergencyWithdraw(address(depositToken));
    }
}
