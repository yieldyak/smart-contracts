// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../BaseStrategy.sol";
import "./interfaces/IDepositHelper.sol";
import "./interfaces/IMasterPenpie.sol";
import "./interfaces/ISy.sol";
import "./interfaces/IPendleRouter.sol";
import "./interfaces/IPendleStaticRouter.sol";

contract PenpieStrategy is BaseStrategy {
    using SafeERC20 for IERC20;

    address private constant PNP = 0x2Ac2B254Bc18cD4999f64773a966E4f4869c34Ee;

    struct PenpieStrategySettings {
        address masterPenpie;
        address depositHelper;
        address tokenLpIn;
        address pendleStaticRouter;
        address pendleRouter;
        address pendleSY;
        address pendleMarket;
    }

    address immutable masterPenpie;
    address immutable depositHelper;
    address immutable magpiePendleStaking;
    address immutable tokenLpIn;
    address immutable pendleStaticRouter;
    address immutable pendleRouter;
    address immutable pendleSY;
    address immutable pendleMarket;

    constructor(
        PenpieStrategySettings memory _penpieStrategySettings,
        BaseStrategySettings memory _variableRewardsStrategySettings,
        StrategySettings memory _strategySettings
    ) BaseStrategy(_variableRewardsStrategySettings, _strategySettings) {
        masterPenpie = _penpieStrategySettings.masterPenpie;
        depositHelper = _penpieStrategySettings.depositHelper;
        magpiePendleStaking = IDepositHelper(depositHelper).pendleStaking();
        pendleStaticRouter = _penpieStrategySettings.pendleStaticRouter;
        pendleRouter = _penpieStrategySettings.pendleRouter;
        pendleSY = _penpieStrategySettings.pendleSY;
        pendleMarket = _penpieStrategySettings.pendleMarket;
        tokenLpIn = _penpieStrategySettings.tokenLpIn;
    }

    function _depositToStakingContract(uint256 _amount, uint256) internal override {
        depositToken.approve(magpiePendleStaking, _amount);
        IDepositHelper(depositHelper).depositMarket(address(depositToken), _amount);
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 _withdrawAmount) {
        IDepositHelper(depositHelper).withdrawMarket(address(depositToken), _amount);
        return _amount;
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        Reward[] memory pendingRewards = new Reward[](supportedRewards.length);
        for (uint256 i; i < pendingRewards.length; i++) {
            address reward = supportedRewards[i];
            (uint256 pendingPenpie,,, uint256 pendingBonusToken) =
                IMasterPenpie(masterPenpie).pendingTokens(address(depositToken), address(this), reward);
            pendingRewards[i] = Reward({reward: reward, amount: reward == PNP ? pendingPenpie : pendingBonusToken});
        }
        return pendingRewards;
    }

    function _getRewards() internal override {
        address[] memory stakingTokens = new address[](1);
        stakingTokens[0] = address(depositToken);
        IMasterPenpie(masterPenpie).multiclaim(stakingTokens);
    }

    function totalDeposits() public view override returns (uint256) {
        (uint256 stakedAmount,) = IMasterPenpie(masterPenpie).stakingInfo(address(depositToken), address(this));
        return stakedAmount;
    }

    function _convertRewardTokenToDepositToken(uint256 _fromAmount) internal override returns (uint256 toAmount) {
        if (_fromAmount == 0) return 0;

        if (address(rewardToken) != tokenLpIn) {
            FormattedOffer memory offer = simpleRouter.query(_fromAmount, address(rewardToken), tokenLpIn);
            _fromAmount = _swap(offer);
        }

        uint256 minOut = ISy(pendleSY).previewDeposit(tokenLpIn, _fromAmount);
        IPendleRouter.TokenInput memory tokenInput = IPendleRouter.TokenInput({
            tokenIn: tokenLpIn,
            netTokenIn: _fromAmount,
            tokenMintSy: tokenLpIn,
            bulk: address(0),
            pendleSwap: address(0),
            swapData: IPendleRouter.SwapData({
                swapType: IPendleRouter.SwapType.NONE,
                extRouter: address(0),
                extCalldata: "",
                needScale: false
            })
        });
        IERC20(tokenLpIn).approve(pendleRouter, _fromAmount);
        uint256 syOut = IPendleRouter(pendleRouter).mintSyFromToken(address(this), pendleSY, minOut, tokenInput);

        (uint256 netLpOut, uint256 netPtFromSwap,,,,) =
            IPendleStaticRouter(pendleStaticRouter).addLiquiditySingleSyStatic(pendleMarket, syOut);
        IPendleRouter.ApproxParams memory approxParams = IPendleRouter.ApproxParams({
            guessMin: netPtFromSwap,
            guessMax: netPtFromSwap,
            guessOffchain: 0,
            maxIteration: 1,
            eps: 1e15
        });
        IERC20(pendleSY).approve(pendleRouter, syOut);
        (toAmount,) =
            IPendleRouter(pendleRouter).addLiquiditySingleSy(address(this), pendleMarket, syOut, netLpOut, approxParams);
    }

    function _emergencyWithdraw() internal override {
        (uint256 stakedAmount,) = IMasterPenpie(masterPenpie).stakingInfo(address(depositToken), address(this));
        IDepositHelper(depositHelper).withdrawMarket(address(depositToken), stakedAmount);
    }
}
