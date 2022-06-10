// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../VariableRewardsStrategyForLP.sol";

import "./interfaces/IHakuChef.sol";

contract HakuStrategyForLP is VariableRewardsStrategyForLP {
    address private constant HAKU = 0x695Fa794d59106cEbd40ab5f5cA19F458c723829;

    IHakuChef public hakuChef;
    uint256 public immutable PID;

    constructor(
        address _stakingContract,
        uint256 _pid,
        SwapPairs memory _swapPairs,
        RewardSwapPairs[] memory _rewardSwapPairs,
        BaseSettings memory _baseSettings,
        StrategySettings memory _strategySettings
    ) VariableRewardsStrategyForLP(_swapPairs, _rewardSwapPairs, _baseSettings, _strategySettings) {
        hakuChef = IHakuChef(_stakingContract);
        PID = _pid;
    }

    function _depositToStakingContract(uint256 _amount) internal override {
        IERC20(asset).approve(address(hakuChef), _amount);
        hakuChef.deposit(PID, _amount);
        IERC20(asset).approve(address(hakuChef), 0);
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 _withdrawAmount) {
        hakuChef.withdraw(PID, _amount);
        return _amount;
    }

    function _emergencyWithdraw() internal override {
        IERC20(asset).approve(address(hakuChef), 0);
        hakuChef.emergencyWithdraw(PID);
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        uint256 pendingHaku = hakuChef.pendingCake(PID, address(this));

        Reward[] memory pendingRewards = new Reward[](1);
        pendingRewards[0] = Reward({reward: HAKU, amount: pendingHaku});
        return pendingRewards;
    }

    function _getRewards() internal override {
        hakuChef.deposit(PID, 0);
    }

    function totalAssets() public view override returns (uint256) {
        (uint256 amount, ) = hakuChef.userInfo(PID, address(this));
        return amount;
    }
}
