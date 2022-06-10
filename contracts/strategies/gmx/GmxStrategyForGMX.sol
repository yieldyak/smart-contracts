// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../VariableRewardsStrategyForSA.sol";
import "../../interfaces/IERC20.sol";
import "../../interfaces/IWAVAX.sol";
import "../../lib/SafeERC20.sol";

import "./interfaces/IGmxProxy.sol";
import "./interfaces/IGmxRewardRouter.sol";

contract GmxStrategyForGMX is VariableRewardsStrategyForSA {
    using SafeERC20 for IERC20;

    IGmxProxy public proxy;

    constructor(
        address _gmxProxy,
        address _swapPairDepositToken,
        RewardSwapPairs[] memory _rewardSwapPairs,
        BaseSettings memory _baseSettings,
        StrategySettings memory _strategySettings
    ) VariableRewardsStrategyForSA(_swapPairDepositToken, _rewardSwapPairs, _baseSettings, _strategySettings) {
        proxy = IGmxProxy(_gmxProxy);
    }

    function setProxy(address _proxy) external onlyOwner {
        proxy = IGmxProxy(_proxy);
    }

    function _depositToStakingContract(uint256 _amount) internal override {
        IERC20(asset).safeTransfer(address(proxy), _amount);
        proxy.stakeGmx(_amount);
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 _withdrawAmount) {
        proxy.withdrawGmx(_amount);
        return _amount;
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        Reward[] memory pendingRewards = new Reward[](1);
        pendingRewards[0] = Reward({reward: address(WAVAX), amount: proxy.pendingRewards(_rewardTracker())});
        return pendingRewards;
    }

    function _getRewards() internal override {
        proxy.claimReward(_rewardTracker());
    }

    function totalAssets() public view override returns (uint256) {
        return _gmxDepositBalance();
    }

    function _emergencyWithdraw() internal override {
        uint256 balance = _gmxDepositBalance();
        proxy.emergencyWithdrawGMX(balance);
    }

    function _gmxDepositBalance() private view returns (uint256) {
        return proxy.totalDeposits(_rewardTracker());
    }

    function _rewardTracker() private view returns (address) {
        address gmxRewardRouter = proxy.gmxRewardRouter();
        return IGmxRewardRouter(gmxRewardRouter).feeGmxTracker();
    }
}
