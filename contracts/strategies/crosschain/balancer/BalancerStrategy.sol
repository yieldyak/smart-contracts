// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../BaseStrategy.sol";

import "./interfaces/IBalancerVault.sol";
import "./interfaces/IBalancerPool.sol";
import "./interfaces/IBalancerGauge.sol";
import "./interfaces/IBalMinter.sol";

abstract contract BalancerStrategy is BaseStrategy {
    using SafeERC20 for IERC20;

    IBalancerGauge public immutable stakingContract;
    IBalancerVault public immutable balancerVault;
    IBalMinter public immutable balMinter;
    bytes32 public immutable poolId;
    address public immutable balancerPoolTokenIn;
    address public immutable gaugeFactory;

    uint256 public boostFeeBips;
    address public boostFeeReceiver;

    address internal immutable BAL;
    address[] internal poolTokens;

    struct BalancerStrategySettings {
        address stakingContract;
        address balancerVault;
        address balancerPoolTokenIn;
        uint256 boostFeeBips;
        address boostFeeReceiver;
    }

    constructor(
        BalancerStrategySettings memory _balancerStrategySettings,
        BaseStrategySettings memory _settings,
        StrategySettings memory _strategySettings
    ) BaseStrategy(_settings, _strategySettings) {
        stakingContract = IBalancerGauge(_balancerStrategySettings.stakingContract);
        gaugeFactory = stakingContract.factory();
        balancerVault = IBalancerVault(_balancerStrategySettings.balancerVault);
        balancerPoolTokenIn = _balancerStrategySettings.balancerPoolTokenIn;
        boostFeeBips = _balancerStrategySettings.boostFeeBips;
        boostFeeReceiver = _balancerStrategySettings.boostFeeReceiver;
        balMinter = IBalMinter(stakingContract.bal_pseudo_minter());
        poolId = IBalancerPool(address(depositToken)).getPoolId();
        BAL = stakingContract.bal_token();
        (poolTokens,,) = balancerVault.getPoolTokens(poolId);
    }

    function updateBoostFeeSettings(address _boostFeeReceiver, uint256 _boostFeeBips) external onlyDev {
        boostFeeReceiver = _boostFeeReceiver;
        boostFeeBips = min(_boostFeeBips, BIPS_DIVISOR);
    }

    function _depositToStakingContract(uint256 _amount, uint256) internal override {
        depositToken.approve(address(stakingContract), _amount);
        stakingContract.deposit(_amount);
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
        Reward[] memory pendingRewards = new Reward[](stakingContract.reward_count() + 1);
        for (uint256 i = 0; i < pendingRewards.length - 1; i++) {
            address rewardToken = stakingContract.reward_tokens(i);
            uint256 amount = stakingContract.claimable_reward(address(this), rewardToken);
            pendingRewards[i] = Reward({reward: rewardToken, amount: amount});
        }
        pendingRewards[pendingRewards.length - 1] = Reward({reward: BAL, amount: _pendingBalRewards()});
        return pendingRewards;
    }

    function _pendingBalRewards() internal view returns (uint256 pendingBal) {
        if (!balMinter.isValidGaugeFactory(address(gaugeFactory))) return 0;

        uint256 period = stakingContract.period();
        uint256 periodTime = stakingContract.period_timestamp(period);
        uint256 integrateInvSupply = stakingContract.integrate_inv_supply(period);

        uint256 workingSupply = stakingContract.working_supply();
        if (block.timestamp > periodTime && !stakingContract.is_killed()) {
            uint256 prevWeekTime = periodTime;
            uint256 weekTime = min(((periodTime + 1 weeks) / 1 weeks * 1 weeks), block.timestamp);
            while (true) {
                uint256 dt = weekTime - prevWeekTime;
                if (workingSupply != 0) {
                    integrateInvSupply +=
                        stakingContract.inflation_rate(prevWeekTime / 1 weeks) * 10e18 * dt / workingSupply;
                }
                if (weekTime == block.timestamp) {
                    break;
                }
                prevWeekTime = weekTime;
                weekTime = min(weekTime + 1 weeks, block.timestamp);
            }
        }

        pendingBal = (
            stakingContract.working_balances(address(this))
                * (integrateInvSupply - stakingContract.integrate_inv_supply_of(address(this))) / 10e18
        ) - balMinter.minted(address(this), address(stakingContract));

        if (boostFeeReceiver > address(0)) {
            pendingBal -= (pendingBal * boostFeeBips) / BIPS_DIVISOR;
        }
    }

    function min(uint256 a, uint256 b) private pure returns (uint256) {
        return a <= b ? a : b;
    }

    function _getRewards() internal override {
        stakingContract.claim_rewards();
        if (balMinter.isValidGaugeFactory(address(gaugeFactory))) {
            balMinter.mint(address(stakingContract));
            if (boostFeeReceiver > address(0)) {
                uint256 boostFee = (IERC20(BAL).balanceOf(address(this)) * boostFeeBips) / BIPS_DIVISOR;
                if (boostFee > 0) {
                    IERC20(BAL).safeTransfer(boostFeeReceiver, boostFee);
                }
            }
        }
    }

    function totalDeposits() public view override returns (uint256) {
        return stakingContract.balanceOf(address(this));
    }

    function _convertRewardTokenToDepositToken(uint256 _fromAmount)
        internal
        virtual
        override
        returns (uint256 toAmount)
    {
        if (address(rewardToken) != balancerPoolTokenIn) {
            FormattedOffer memory offer = simpleRouter.query(_fromAmount, address(rewardToken), balancerPoolTokenIn);
            _fromAmount = _swap(offer);
        }

        return _joinPool(_fromAmount);
    }

    function _joinPool(uint256 _amountIn) internal virtual returns (uint256 amountOut);
}
