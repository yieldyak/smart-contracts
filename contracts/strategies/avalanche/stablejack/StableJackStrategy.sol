// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../../BaseStrategy.sol";
import "./interfaces/IRebalancePool.sol";
import "./interfaces/IHarvestableTreasury.sol";

contract StableJackStrategy is BaseStrategy {
    IRebalancePool public immutable rebalancePool;
    address public immutable baseRewardToken;

    constructor(
        address _rebalancePool,
        BaseStrategySettings memory _baseStrategySettings,
        StrategySettings memory _strategySettings
    ) BaseStrategy(_baseStrategySettings, _strategySettings) {
        rebalancePool = IRebalancePool(_rebalancePool);
        baseRewardToken = rebalancePool.baseRewardToken();
    }

    function _depositToStakingContract(uint256 _amount, uint256) internal override {
        require(rebalancePool.unlockDuration() == 0, "StableJackStrategy::deposits disabled");
        depositToken.approve(address(rebalancePool), _amount);
        rebalancePool.deposit(_amount, address(this));
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 _withdrawAmount) {
        rebalancePool.unlock(_amount);
        rebalancePool.withdrawUnlocked(false, false);
        return _amount;
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        uint256 extraRewardsCount = rebalancePool.extraRewardsLength();

        Reward[] memory rewards = new Reward[](extraRewardsCount + 1);
        Reward({reward: baseRewardToken, amount: rebalancePool.claimable(address(this), baseRewardToken)});

        for (uint256 i; i < extraRewardsCount; i++) {
            address extraReward = rebalancePool.extraRewards(i);
            rewards[i] = Reward({
                reward: extraReward,
                amount: extraReward != baseRewardToken ? rebalancePool.claimable(address(this), extraReward) : 0
            });
        }

        return rewards;
    }

    function _getRewards() internal override {
        uint256 extraRewardsCount = rebalancePool.extraRewardsLength();
        address[] memory extraRewards = new address[](extraRewardsCount);

        bool baseRewardIncluded;
        for (uint256 i; i < extraRewardsCount; i++) {
            extraRewards[i] = rebalancePool.extraRewards(i);

            if (extraRewards[i] == baseRewardToken) {
                baseRewardIncluded = true;
            }
        }

        address[] memory rewards = baseRewardIncluded ? extraRewards : new address[](extraRewardsCount + 1);
        if (!baseRewardIncluded) {
            rewards[0] = baseRewardToken;
            for (uint256 i = 1; i < rewards.length; i++) {
                rewards[i] = extraRewards[i - 1];
            }
        }

        for (uint256 i; i < rewards.length; i++) {
            IHarvestableTreasury(rebalancePool.rewardManager(rewards[i])).harvest();
        }

        try rebalancePool.claim(rewards, true) {} catch {}
    }

    function totalDeposits() public view override returns (uint256) {
        return rebalancePool.balanceOf(address(this));
    }

    function _emergencyWithdraw() internal override {
        rebalancePool.unlock(totalDeposits());
        rebalancePool.withdrawUnlocked(false, false);
        depositToken.approve(address(rebalancePool), 0);
    }
}
