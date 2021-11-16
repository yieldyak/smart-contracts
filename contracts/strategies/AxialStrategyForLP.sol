// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity ^0.7.0;

import "../interfaces/IAxialChef.sol";
import "../interfaces/IAxialSwap.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IPair.sol";
import "../lib/DexLibrary.sol";
import "./MasterChefStrategy.sol";

contract AxialStrategyForLP is MasterChefStrategy {
    using SafeMath for uint256;

    IWAVAX private constant WAVAX = IWAVAX(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);

    IAxialChef public axialChef;
    ZapSettings private zapSettings;

    /**
     * @dev IAxialSwap assumes amounts to be 18 decimals. Use token with 18 decimals!
     */
    struct ZapSettings {
        address swapPairRewardZap;
        address zapToken;
        address zapContract;
        uint256 maxSlippage;
    }

    constructor(
        string memory _name,
        address _depositToken,
        address _poolRewardToken,
        address _swapPairPoolReward,
        address _swapPairExtraReward,
        address _stakingContract,
        ZapSettings memory _zapSettings,
        uint256 _pid,
        address _timelock,
        StrategySettings memory _strategySettings
    )
        MasterChefStrategy(
            _name,
            _depositToken,
            address(WAVAX), /*rewardToken=*/
            _poolRewardToken,
            _swapPairPoolReward,
            _swapPairExtraReward,
            _stakingContract,
            _timelock,
            _pid,
            _strategySettings
        )
    {
        axialChef = IAxialChef(_stakingContract);
        zapSettings = _zapSettings;
        IERC20(zapSettings.zapToken).approve(zapSettings.zapContract, type(uint256).max);
    }

    function _depositMasterchef(uint256 _pid, uint256 _amount) internal override {
        axialChef.deposit(_pid, _amount);
    }

    function _withdrawMasterchef(uint256 _pid, uint256 _amount) internal override {
        axialChef.withdraw(_pid, _amount);
    }

    function _emergencyWithdraw(uint256 _pid) internal override {
        axialChef.emergencyWithdraw(_pid);
    }

    function _pendingRewards(uint256 _pid, address _user)
        internal
        view
        override
        returns (
            uint256,
            uint256,
            address
        )
    {
        (uint256 pendingAxial, address bonusTokenAddress, , uint256 pendingBonusToken) = axialChef.pendingTokens(
            _pid,
            _user
        );
        return (pendingAxial, pendingBonusToken, bonusTokenAddress);
    }

    function _getRewards(uint256 _pid) internal override {
        axialChef.withdraw(_pid, 0);
    }

    function _getDepositBalance(uint256 pid, address user) internal view override returns (uint256 amount) {
        (amount, ) = axialChef.userInfo(pid, user);
    }

    function setMaxSlippageBips(uint256 _maxSlippageBips) external onlyDev {
        zapSettings.maxSlippage = _maxSlippageBips;
    }

    function _getDepositFeeBips(
        uint256 /* pid */
    ) internal pure override returns (uint256) {
        return 0;
    }

    function _getWithdrawFeeBips(
        uint256 /* pid */
    ) internal pure override returns (uint256) {
        return 0;
    }

    function _bip() internal pure override returns (uint256) {
        return 10000;
    }

    function _convertRewardTokenToDepositToken(uint256 fromAmount) internal override returns (uint256 toAmount) {
        uint256 zapTokenAmount = DexLibrary.swap(
            fromAmount,
            address(rewardToken),
            zapSettings.zapToken,
            IPair(zapSettings.swapPairRewardZap)
        );
        uint256[] memory amounts = new uint256[](4);
        uint256 zapTokenIndex = IAxialSwap(zapSettings.zapContract).getTokenIndex(zapSettings.zapToken);
        amounts[zapTokenIndex] = zapTokenAmount;
        uint256 slippage = zapTokenAmount.mul(zapSettings.maxSlippage).div(BIPS_DIVISOR);
        return
            IAxialSwap(zapSettings.zapContract).addLiquidity(amounts, zapTokenAmount.sub(slippage), type(uint256).max);
    }
}
