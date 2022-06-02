// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../VariableRewardsStrategyForLP.sol";
import "../../lib/SafeERC20.sol";

import "./interfaces/IJoeChef.sol";
import "./interfaces/IJoeVoterProxy.sol";

contract BoostedJoeStrategyForLP is VariableRewardsStrategyForLP {
    using SafeERC20 for IERC20;

    address private constant JOE = 0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd;

    address public stakingContract;
    uint256 public immutable PID;
    IJoeVoterProxy public proxy;
    address public swapPairRewardToken;
    address public extraToken;

    constructor(
        address _stakingContract,
        uint256 _pid,
        address _extraToken,
        address _voterProxy,
        SwapPairs memory _swapPairs,
        RewardSwapPairs[] memory _rewardSwapPairs,
        BaseSettings memory _baseSettings,
        StrategySettings memory _strategySettings
    ) VariableRewardsStrategyForLP(_swapPairs, _rewardSwapPairs, _baseSettings, _strategySettings) {
        stakingContract = _stakingContract;
        proxy = IJoeVoterProxy(_voterProxy);
        extraToken = _extraToken;
        PID = _pid;
    }

    function _depositToStakingContract(uint256 _amount) internal override {
        IERC20(asset).safeTransfer(address(proxy), _amount);
        proxy.deposit(PID, stakingContract, asset, _amount);
        proxy.distributeReward(PID, stakingContract, address(extraToken));
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 _withdrawAmount) {
        proxy.withdraw(PID, stakingContract, asset, _amount);
        proxy.distributeReward(PID, stakingContract, address(extraToken));
        return _amount;
    }

    function _emergencyWithdraw() internal override {
        IERC20(asset).approve(address(proxy), 0);
        proxy.emergencyWithdraw(PID, stakingContract, asset);
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        (uint256 pendingJoe, address bonusTokenAddress, uint256 pendingBonusToken) = proxy.pendingRewards(
            stakingContract,
            PID
        );

        Reward[] memory pendingRewards = new Reward[](2);
        pendingRewards[0] = Reward({reward: JOE, amount: pendingJoe});
        pendingRewards[1] = Reward({reward: bonusTokenAddress, amount: pendingBonusToken});
        return pendingRewards;
    }

    function _getRewards() internal override {
        proxy.claimReward(PID, stakingContract, address(extraToken));
    }

    function addReward(address _rewardToken, address _swapPair) public override onlyDev {
        super.addReward(_rewardToken, _swapPair);
        if (_rewardToken != JOE) {
            extraToken = _rewardToken;
        }
    }

    function removeReward(address _rewardToken) public override onlyDev {
        super.removeReward(_rewardToken);
        if (_rewardToken == extraToken) {
            extraToken = address(0);
        }
    }

    function totalAssets() public view override returns (uint256) {
        return proxy.poolBalance(stakingContract, PID);
    }
}
