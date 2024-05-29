// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../../BaseStrategy.sol";
import "./interfaces/IStargateStaking.sol";
import "./interfaces/IStargateMultiRewarder.sol";
import "./interfaces/IStargatePool.sol";

contract StargateV2Strategy is BaseStrategy {
    IStargateStaking immutable stargateStaking;
    IStargatePool immutable stargatePool;
    address immutable underlying;

    constructor(
        address _stargateStaking,
        address _pool,
        BaseStrategySettings memory _baseStrategySettings,
        StrategySettings memory _strategySettings
    ) BaseStrategy(_baseStrategySettings, _strategySettings) {
        stargateStaking = IStargateStaking(_stargateStaking);
        stargatePool = IStargatePool(_pool);
        underlying = stargatePool.token();
    }

    function _depositToStakingContract(uint256 _amount, uint256) internal override {
        depositToken.approve(address(stargateStaking), _amount);
        stargateStaking.deposit(address(depositToken), _amount);
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 _withdrawAmount) {
        stargateStaking.withdraw(address(depositToken), _amount);
        return _amount;
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        (address[] memory tokens, uint256[] memory amounts) = IStargateMultiRewarder(
            stargateStaking.rewarder(address(depositToken))
        ).getRewards(address(depositToken), address(this));

        Reward[] memory rewards = new Reward[](tokens.length);
        for (uint256 i; i < rewards.length; i++) {
            rewards[i] = Reward({reward: tokens[i], amount: amounts[i]});
        }

        return rewards;
    }

    function _getRewards() internal override {
        address[] memory tokens = new address[](1);
        tokens[0] = address(depositToken);
        stargateStaking.claim(tokens);
    }

    function _convertRewardTokenToDepositToken(uint256 _fromAmount) internal override returns (uint256 toAmount) {
        if (address(rewardToken) != underlying) {
            FormattedOffer memory offer = simpleRouter.query(_fromAmount, address(rewardToken), underlying);
            _fromAmount = _swap(offer);
        }
        IERC20(underlying).approve(address(stargatePool), _fromAmount);
        return stargatePool.deposit(address(this), _fromAmount);
    }

    function totalDeposits() public view override returns (uint256) {
        return stargateStaking.balanceOf(address(depositToken), address(this));
    }

    function _emergencyWithdraw() internal override {
        stargateStaking.emergencyWithdraw(address(depositToken));
        depositToken.approve(address(stargateStaking), 0);
    }
}
