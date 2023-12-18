// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../../BaseStrategy.sol";
import "./interfaces/IMultiRewards.sol";

contract DopexStrategyForSA is BaseStrategy {
    IMultiRewards immutable rewarder;

    constructor(
        address _stakingContract,
        BaseStrategySettings memory _baseStrategySettings,
        StrategySettings memory _strategySettings
    ) BaseStrategy(_baseStrategySettings, _strategySettings) {
        rewarder = IMultiRewards(_stakingContract);
    }

    function _depositToStakingContract(uint256 _amount, uint256) internal override {
        depositToken.approve(address(rewarder), _amount);
        rewarder.stake(_amount);
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 _withdrawAmount) {
        rewarder.withdraw(_amount);
        return _amount;
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        Reward[] memory pendingRewards = new Reward[](supportedRewards.length);
        for (uint256 i; i < pendingRewards.length; i++) {
            address reward = supportedRewards[i];
            uint256 pending = rewarder.earned(address(this), reward);
            pendingRewards[i] = Reward({reward: reward, amount: pending});
        }
        return pendingRewards;
    }

    function _getRewards() internal override {
        rewarder.getReward();
    }

    function totalDeposits() public view override returns (uint256) {
        return rewarder.balanceOf(address(this));
    }

    function _emergencyWithdraw() internal override {
        rewarder.exit();
        depositToken.approve(address(rewarder), 0);
    }
}
