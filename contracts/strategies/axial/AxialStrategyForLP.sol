// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../VariableRewardsStrategy.sol";
import "../../interfaces/IERC20.sol";
import "../../interfaces/IPair.sol";
import "../../lib/DexLibrary.sol";

import "./interfaces/IAxialChef.sol";
import "./interfaces/IAxialSwap.sol";

contract AxialStrategyForLP is VariableRewardsStrategy {
    address private constant AXIAL = 0xcF8419A615c57511807236751c0AF38Db4ba3351;

    IAxialChef public axialChef;
    uint256 public immutable PID;

    ZapSettings private zapSettings;

    /**
     * @dev IAxialSwap assumes amounts to be 18 decimals. Use token with 18 decimals!
     */
    struct ZapSettings {
        uint256 tokenCount;
        address swapPairRewardZap;
        address zapToken;
        address zapContract;
        uint256 maxSlippage;
    }

    constructor(
        address _stakingContract,
        uint256 _pid,
        ZapSettings memory _zapSettings,
        RewardSwapPairs[] memory _rewardSwapPairs,
        BaseSettings memory _baseSettings,
        StrategySettings memory _strategySettings
    ) VariableRewardsStrategy(_rewardSwapPairs, _baseSettings, _strategySettings) {
        axialChef = IAxialChef(_stakingContract);
        zapSettings = _zapSettings;
        IERC20(zapSettings.zapToken).approve(zapSettings.zapContract, type(uint256).max);
        PID = _pid;
    }

    function _depositToStakingContract(uint256 _amount) internal override {
        IERC20(asset).approve(address(axialChef), _amount);
        axialChef.deposit(PID, _amount);
        IERC20(asset).approve(address(axialChef), 0);
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 _withdrawAmount) {
        axialChef.withdraw(PID, _amount);
        return _amount;
    }

    function _emergencyWithdraw() internal override {
        axialChef.emergencyWithdraw(PID);
        IERC20(asset).approve(address(axialChef), 0);
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        (uint256 pendingAxial, address bonusTokenAddress, , uint256 pendingBonusToken) = axialChef.pendingTokens(
            PID,
            address(this)
        );

        Reward[] memory pendingRewards = new Reward[](2);
        pendingRewards[0] = Reward({reward: AXIAL, amount: pendingAxial});
        pendingRewards[0] = Reward({reward: bonusTokenAddress, amount: pendingBonusToken});
        return pendingRewards;
    }

    function _getRewards() internal override {
        axialChef.withdraw(PID, 0);
    }

    function totalAssets() public view override returns (uint256) {
        (uint256 amount, ) = axialChef.userInfo(PID, address(this));
        return amount;
    }

    function updateMaxSwapSlippage(uint256 _maxSlippageBips) external onlyDev {
        zapSettings.maxSlippage = _maxSlippageBips;
    }

    function _convertRewardTokenToDepositToken(uint256 fromAmount) internal override returns (uint256 toAmount) {
        uint256 zapTokenAmount = DexLibrary.swap(
            fromAmount,
            address(rewardToken),
            zapSettings.zapToken,
            IPair(zapSettings.swapPairRewardZap)
        );
        uint256[] memory amounts = new uint256[](zapSettings.tokenCount);
        uint256 zapTokenIndex = IAxialSwap(zapSettings.zapContract).getTokenIndex(zapSettings.zapToken);
        amounts[zapTokenIndex] = zapTokenAmount;
        uint256 slippage = (zapTokenAmount * zapSettings.maxSlippage) / BIPS_DIVISOR;
        return IAxialSwap(zapSettings.zapContract).addLiquidity(amounts, zapTokenAmount - slippage, type(uint256).max);
    }
}
