// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../../VariableRewardsStrategyForSA.sol";

import "./interfaces/IPool.sol";

contract DeltaPrimeDepositorStrategy is VariableRewardsStrategyForSA {
    using SafeERC20 for IERC20;

    IPool public immutable pool;

    constructor(
        address _pool,
        VariableRewardsStrategySettings memory _variableRewardsStrategySettings,
        StrategySettings memory _strategySettings
    ) VariableRewardsStrategyForSA(address(0), _variableRewardsStrategySettings, _strategySettings) {
        pool = IPool(_pool);
    }

    receive() external payable {
        require(msg.sender == address(pool.poolRewarder()));
    }

    function _depositToStakingContract(uint256 _amount, uint256) internal override {
        depositToken.approve(address(pool), _amount);
        pool.deposit(_amount);
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 _withdrawAmount) {
        pool.withdraw(_amount);
        return _amount;
    }

    function _emergencyWithdraw() internal override {
        pool.withdraw(totalDeposits());
    }

    function _pendingRewards() internal view override returns (Reward[] memory pendingRewards) {
        uint256 count = rewardCount;
        if (count > 0) {
            pendingRewards = new Reward[](1);
            pendingRewards[0] = Reward({reward: supportedRewards[0], amount: pool.checkRewards()});
        }
    }

    function _getRewards() internal override {
        pool.getRewards();
    }

    function totalDeposits() public view override returns (uint256) {
        return pool.balanceOf(address(this));
    }
}
