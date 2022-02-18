// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity ^0.7.0;

import "../interfaces/IStableJoeStaking.sol";
import "../interfaces/IPangolinRewarder.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IPair.sol";
import "../lib/DexLibrary.sol";
import "./MasterChefVariableRewardsStrategyForSA.sol";

contract CompoundingJoeV3 is MasterChefVariableRewardsStrategyForSA {
    using SafeMath for uint256;

    IStableJoeStaking public stakingContract;
    address private poolRewardToken;

    constructor(
        string memory _name,
        address _depositToken,
        address _rewardToken,
        address _poolRewardToken,
        address _swapPairToken,
        ExtraReward[] memory _extraRewards,
        address _stakingContract,
        address _timelock,
        StrategySettings memory _strategySettings
    )
        MasterChefVariableRewardsStrategyForSA(
            _name,
            _depositToken,
            _rewardToken,
            _poolRewardToken,
            _swapPairToken,
            _extraRewards,
            _stakingContract,
            _timelock,
            0,
            _strategySettings
        )
    {
        poolRewardToken = _poolRewardToken;
        stakingContract = IStableJoeStaking(_stakingContract);
    }

    function _depositMasterchef(
        uint256, /*_pid*/
        uint256 _amount
    ) internal override {
        depositToken.approve(address(stakingContract), _amount);
        stakingContract.deposit(_amount);
    }

    function _withdrawMasterchef(
        uint256, /*_pid*/
        uint256 _amount
    ) internal override {
        stakingContract.withdraw(_amount);
    }

    function _emergencyWithdraw(
        uint256 /*_pid*/
    ) internal override {
        stakingContract.emergencyWithdraw();
        depositToken.approve(address(stakingContract), 0);
    }

    function _pendingRewards(
        uint256 /*_pid*/
    ) internal view override returns (Reward[] memory) {
        uint256 rewardCount = stakingContract.rewardTokensLength();
        Reward[] memory pendingRewards = new Reward[](rewardCount);
        for (uint256 i = 0; i < rewardCount; i++) {
            address rewardToken = stakingContract.rewardTokens(i);
            uint256 amount = stakingContract.pendingReward(address(this), rewardToken);
            pendingRewards[i] = Reward({reward: rewardToken, amount: amount});
        }
        return pendingRewards;
    }

    function _getRewards(
        uint256 /*_pid*/
    ) internal override {
        stakingContract.deposit(0);
    }

    function _getDepositBalance(
        uint256 /*_pid*/
    ) internal view override returns (uint256 amount) {
        (amount, ) = stakingContract.getUserInfo(address(this), address(0));
    }

    function _getDepositFeeBips(
        uint256 /*_pid*/
    ) internal view override returns (uint256) {
        return stakingContract.depositFeePercent();
    }

    function _getWithdrawFeeBips(
        uint256 /*_pid*/
    ) internal pure override returns (uint256) {
        return 0;
    }

    function _bip() internal view override returns (uint256) {
        return stakingContract.PRECISION();
    }
}
