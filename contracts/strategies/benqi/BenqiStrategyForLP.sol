// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../VariableRewardsStrategyForLP.sol";

import "./interfaces/IBenqiStakingContract.sol";

contract BenqiStrategyForLP is VariableRewardsStrategyForLP {
    address private constant QI = 0x8729438EB15e2C8B576fCc6AeCdA6A148776C0F5;

    IBenqiStakingContract public stakingContract;

    constructor(
        address _stakingContract,
        SwapPairs memory _swapPairs,
        RewardSwapPairs[] memory _rewardSwapPairs,
        BaseSettings memory _baseSettings,
        StrategySettings memory _strategySettings
    ) VariableRewardsStrategyForLP(_swapPairs, _rewardSwapPairs, _baseSettings, _strategySettings) {
        stakingContract = IBenqiStakingContract(_stakingContract);
    }

    receive() external payable {}

    function _depositToStakingContract(uint256 _amount) internal override {
        IERC20(asset).approve(address(stakingContract), _amount);
        stakingContract.deposit(_amount);
        IERC20(asset).approve(address(stakingContract), 0);
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 _withdrawAmount) {
        stakingContract.redeem(_amount);
        _withdrawAmount = _amount;
    }

    function _emergencyWithdraw() internal override {
        stakingContract.redeem(stakingContract.supplyAmount(address(this)));
        IERC20(asset).approve(address(stakingContract), 0);
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        Reward[] memory pendingRewards = new Reward[](2);
        uint256 avaxAmount = stakingContract.getClaimableRewards(0);
        uint256 qiAmount = stakingContract.getClaimableRewards(1);

        pendingRewards[0] = Reward({reward: address(WAVAX), amount: avaxAmount});
        pendingRewards[1] = Reward({reward: QI, amount: qiAmount});
        return pendingRewards;
    }

    function _getRewards() internal override {
        stakingContract.claimRewards();
    }

    function totalAssets() public view override returns (uint256) {
        return stakingContract.supplyAmount(address(this));
    }
}
