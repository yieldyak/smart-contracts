// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../../BaseStrategy.sol";
import "./interfaces/ITMStaking.sol";

contract TokenMillStrategy is BaseStrategy {
    ITMStaking immutable tmStaking;

    constructor(
        address _tmStaking,
        BaseStrategySettings memory _baseStrategySettings,
        StrategySettings memory _strategySettings
    ) BaseStrategy(_baseStrategySettings, _strategySettings) {
        tmStaking = ITMStaking(_tmStaking);
    }

    function _depositToStakingContract(uint256 _amount, uint256) internal override {
        depositToken.approve(address(tmStaking), _amount);
        tmStaking.deposit(address(depositToken), address(this), _amount, 0);
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 _withdrawAmount) {
        tmStaking.withdraw(address(depositToken), address(this), _amount);
        return _amount;
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        uint amount = tmStaking.getPendingRewards(address(depositToken), address(this));

        Reward[] memory rewards = new Reward[](1);
            rewards[0] = Reward({reward: address(WGAS), amount: amount});

        return rewards;
    }

    function _getRewards() internal override {
        tmStaking.claimRewards(address(depositToken), address(this));
    }

    function totalDeposits() public view override returns (uint256) {
        (uint amount,) = tmStaking.getStakeOf(address(depositToken), address(this));
        return amount;
    }

    function _emergencyWithdraw() internal override {
        tmStaking.withdraw(address(depositToken), address(this), totalDeposits());
        depositToken.approve(address(tmStaking), 0);
    }
}
