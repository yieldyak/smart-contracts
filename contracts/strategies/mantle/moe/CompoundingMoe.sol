// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../BaseStrategy.sol";

import "./interfaces/IMoeStaking.sol";
import "./interfaces/IStableMoe.sol";

contract CompoundingMoe is BaseStrategy {
    IMoeStaking public moeStaking;

    constructor(address _moeStaking, BaseStrategySettings memory _settings, StrategySettings memory _strategySettings)
        BaseStrategy(_settings, _strategySettings)
    {
        moeStaking = IMoeStaking(_moeStaking);
    }

    function _depositToStakingContract(uint256 _amount, uint256) internal override {
        depositToken.approve(address(moeStaking), _amount);
        moeStaking.stake(_amount);
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 withdrawAmount) {
        moeStaking.unstake(_amount);
        return _amount;
    }

    function _emergencyWithdraw() internal override {
        moeStaking.unstake(totalDeposits());
        depositToken.approve(address(moeStaking), 0);
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        (address[] memory tokens, uint256[] memory amounts) =
            IStableMoe(moeStaking.getSMoe()).getPendingRewards(address(this));
        Reward[] memory pendingRewards = new Reward[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            pendingRewards[i] = Reward({reward: tokens[i], amount: amounts[i]});
        }
        return pendingRewards;
    }

    function _getRewards() internal override {
        moeStaking.claim();
    }

    function totalDeposits() public view override returns (uint256) {
        return moeStaking.getDeposit(address(this));
    }
}
