// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../BaseStrategy.sol";

import "./interfaces/IStakingRewards.sol";
import "./interfaces/ILPToken.sol";
import "./interfaces/ISwap.sol";

contract HopStrategyForLP is BaseStrategy {
    IStakingRewards public immutable stakingContract;
    ISwap public immutable swap;

    address public immutable stakingRewardToken;
    address public immutable lpTokenIn;

    uint256 private immutable addLiquidityIndex;

    constructor(
        address _stakingContract,
        address _lpTokenIn,
        BaseStrategySettings memory _settings,
        StrategySettings memory _strategySettings
    ) BaseStrategy(_settings, _strategySettings) {
        stakingContract = IStakingRewards(_stakingContract);
        stakingRewardToken = stakingContract.rewardsToken();
        swap = ISwap(ILPToken(address(depositToken)).swap());
        lpTokenIn = _lpTokenIn;
        addLiquidityIndex = swap.getTokenIndex(lpTokenIn);
    }

    function _depositToStakingContract(uint256 _amount, uint256) internal override {
        depositToken.approve(address(stakingContract), _amount);
        stakingContract.stake(_amount);
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 withdrawAmount) {
        stakingContract.withdraw(_amount);
        return _amount;
    }

    function _emergencyWithdraw() internal override {
        stakingContract.withdraw(totalDeposits());
        depositToken.approve(address(stakingContract), 0);
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        Reward[] memory pendingRewards = new Reward[](1);
        pendingRewards[0] = Reward({reward: stakingRewardToken, amount: stakingContract.earned(address(this))});
        return pendingRewards;
    }

    function _getRewards() internal override {
        stakingContract.getReward();
    }

    function _convertRewardTokenToDepositToken(uint256 _fromAmount) internal override returns (uint256 toAmount) {
        if (_fromAmount == 0) return 0;

        if (address(rewardToken) != lpTokenIn) {
            FormattedOffer memory offer = simpleRouter.query(_fromAmount, address(rewardToken), lpTokenIn);
            _fromAmount = _swap(offer);
        }

        uint256[] memory amounts = new uint[](2);
        amounts[addLiquidityIndex] = _fromAmount;
        IERC20(lpTokenIn).approve(address(swap), _fromAmount);
        return swap.addLiquidity(amounts, 0, block.timestamp);
    }

    function totalDeposits() public view override returns (uint256) {
        return stakingContract.balanceOf(address(this));
    }
}
