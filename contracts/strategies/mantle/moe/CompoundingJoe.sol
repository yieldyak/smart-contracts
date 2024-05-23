// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../BaseStrategy.sol";

import "./interfaces/IJoeStaking.sol";

contract CompoundingJoe is BaseStrategy {
    IJoeStaking public joeStaking;

    constructor(address _joeStaking, BaseStrategySettings memory _settings, StrategySettings memory _strategySettings)
        BaseStrategy(_settings, _strategySettings)
    {
        joeStaking = IJoeStaking(_joeStaking);
    }

    function _depositToStakingContract(uint256 _amount, uint256) internal override {
        depositToken.approve(address(joeStaking), _amount);
        joeStaking.stake(_amount);
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 withdrawAmount) {
        joeStaking.unstake(_amount);
        return _amount;
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        (address token, uint256 amount) = joeStaking.getPendingReward(address(this));
        Reward[] memory pendingRewards = new Reward[](1);
        pendingRewards[0] = Reward({reward: token, amount: amount});
        return pendingRewards;
    }

    function _getRewards() internal override {
        joeStaking.claim();
    }

    function totalDeposits() public view override returns (uint256) {
        return joeStaking.getDeposit(address(this));
    }

    function _emergencyWithdraw() internal override {
        joeStaking.unstake(totalDeposits());
        depositToken.approve(address(joeStaking), 0);
    }
}
