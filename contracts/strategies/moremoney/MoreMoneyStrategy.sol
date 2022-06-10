// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../VariableRewardsStrategy.sol";
import "../../interfaces/IERC20.sol";
import "../curve/lib/CurveSwap.sol";

import "./interfaces/IMoreMoneyStakingRewards.sol";

contract MoreMoneyStrategy is VariableRewardsStrategy {
    address private constant MORE = 0xd9D90f882CDdD6063959A9d837B05Cb748718A05;

    CurveSwap.Settings private zapSettings;
    address private curvePool;
    IMoreMoneyStakingRewards public stakingContract;

    constructor(
        address _stakingContract,
        CurveSwap.Settings memory _curveSwapSettings,
        RewardSwapPairs[] memory _rewardSwapPairs,
        BaseSettings memory _baseSettings,
        StrategySettings memory _strategySettings
    ) VariableRewardsStrategy(_rewardSwapPairs, _baseSettings, _strategySettings) {
        stakingContract = IMoreMoneyStakingRewards(_stakingContract);
        curvePool = _baseSettings.asset;
        zapSettings = _curveSwapSettings;
        IERC20(zapSettings.zapToken).approve(zapSettings.zapContract, type(uint256).max);
    }

    function setMaxSlippageBips(uint256 _maxSlippageBips) external onlyDev {
        zapSettings.maxSlippage = _maxSlippageBips;
    }

    function _depositToStakingContract(uint256 _amount) internal override {
        IERC20(asset).approve(address(stakingContract), _amount);
        stakingContract.stake(_amount);
        IERC20(asset).approve(address(stakingContract), 0);
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 _withdrawAmount) {
        stakingContract.withdraw(_amount);
        return _amount;
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        if (a >= b) {
            return b;
        } else {
            return a;
        }
    }

    function _earned(address account) private view returns (uint256) {
        return
            (stakingContract.balanceOf(account) *
                ((stakingContract.rewardPerToken() - stakingContract.userRewardPerTokenAccountedFor(account)))) /
            (1e18);
    }

    function _calculateReward(address account) private view returns (uint256) {
        uint256 vStart = stakingContract.vestingStart(account);
        uint256 timeDelta = block.timestamp - vStart;
        uint256 totalRewards = stakingContract.rewards(account) + _earned(account);

        if (stakingContract.vestingPeriod() == 0) {
            return totalRewards;
        } else {
            uint256 rewardVested = vStart > 0 && timeDelta > 0
                ? _min(totalRewards, (totalRewards * timeDelta) / stakingContract.vestingPeriod())
                : 0;
            return rewardVested;
        }
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        uint256 pendingReward = _calculateReward(address(this));
        Reward[] memory pendingRewards = new Reward[](1);
        pendingRewards[0] = Reward({reward: MORE, amount: pendingReward});
        return pendingRewards;
    }

    function _getRewards() internal override {
        stakingContract.withdrawVestedReward();
    }

    function totalAssets() public view override returns (uint256) {
        return stakingContract.balanceOf(address(this));
    }

    function _convertRewardTokenToDepositToken(uint256 fromAmount) internal override returns (uint256 toAmount) {
        return CurveSwap.zapToFactory4AssetsPoolLP(fromAmount, address(rewardToken), asset, zapSettings);
    }

    function _emergencyWithdraw() internal override {
        stakingContract.exit();
    }
}
