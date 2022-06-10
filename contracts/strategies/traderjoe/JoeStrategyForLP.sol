// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../VariableRewardsStrategyForLP.sol";
import "../../interfaces/IERC20.sol";

import "./interfaces/IJoeChef.sol";

contract JoeStrategyForLP is VariableRewardsStrategyForLP {
    address private constant JOE = 0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd;

    IJoeChef public joeChef;
    uint256 public immutable PID;

    constructor(
        address _stakingContract,
        uint256 _pid,
        SwapPairs memory _swapPairs,
        RewardSwapPairs[] memory _rewardSwapPairs,
        BaseSettings memory _baseSettings,
        StrategySettings memory _strategySettings
    ) VariableRewardsStrategyForLP(_swapPairs, _rewardSwapPairs, _baseSettings, _strategySettings) {
        joeChef = IJoeChef(_stakingContract);
        PID = _pid;
    }

    receive() external payable {
        (, , , , address rewarder) = joeChef.poolInfo(PID);
        require(
            msg.sender == rewarder ||
                msg.sender == address(joeChef) ||
                msg.sender == owner() ||
                msg.sender == address(devAddr),
            "not allowed"
        );
    }

    function _depositToStakingContract(uint256 _amount) internal override {
        IERC20(asset).approve(address(joeChef), _amount);
        joeChef.deposit(PID, _amount);
        IERC20(asset).approve(address(joeChef), 0);
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 _withdrawAmount) {
        joeChef.withdraw(PID, _amount);
        return _amount;
    }

    function _emergencyWithdraw() internal override {
        IERC20(asset).approve(address(joeChef), 0);
        joeChef.emergencyWithdraw(PID);
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        (uint256 pendingJoe, address bonusTokenAddress, , uint256 pendingBonusToken) = joeChef.pendingTokens(
            PID,
            address(this)
        );
        Reward[] memory pendingRewards = new Reward[](2);

        pendingRewards[0] = Reward({reward: JOE, amount: pendingJoe});
        pendingRewards[1] = Reward({reward: bonusTokenAddress, amount: pendingBonusToken});
        return pendingRewards;
    }

    function _getRewards() internal override {
        joeChef.deposit(PID, 0);
    }

    function totalAssets() public view override returns (uint256) {
        (uint256 amount, ) = joeChef.userInfo(PID, address(this));
        return amount;
    }
}
