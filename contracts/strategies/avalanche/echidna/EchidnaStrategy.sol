// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../../VariableRewardsStrategyForSA.sol";
import "../../../interfaces/IBoosterFeeCollector.sol";

import "../platypus/lib/PlatypusLibrary.sol";

import "./interfaces/IEchidnaBooster.sol";
import "./interfaces/IEchidnaRewardPool.sol";

contract EchidnaStrategy is VariableRewardsStrategyForSA {
    using SafeERC20 for IERC20;

    struct EchidnaStrategySettings {
        address swapPairDepositToken;
        address stakingContract;
        address platypusPool;
        uint256 pid;
        address boosterFeeCollector;
    }

    IERC20 private constant PTP = IERC20(0x22d4002028f537599bE9f666d1c4Fa138522f9c8);

    uint256 public immutable PID;

    IEchidnaBooster public immutable echidnaBooster;
    IPlatypusPool public immutable platypusPool;
    IPlatypusAsset public immutable platypusAsset;
    IBoosterFeeCollector public boosterFeeCollector;

    constructor(
        EchidnaStrategySettings memory _echidnaStrategySettings,
        VariableRewardsStrategySettings memory _variableRewardsStrategySettings,
        StrategySettings memory _strategySettings
    )
        VariableRewardsStrategyForSA(
            _echidnaStrategySettings.swapPairDepositToken,
            _variableRewardsStrategySettings,
            _strategySettings
        )
    {
        PID = _echidnaStrategySettings.pid;
        platypusPool = IPlatypusPool(_echidnaStrategySettings.platypusPool);
        echidnaBooster = IEchidnaBooster(_echidnaStrategySettings.stakingContract);
        platypusAsset = IPlatypusAsset(
            IPlatypusPool(_echidnaStrategySettings.platypusPool).assetOf(_strategySettings.depositToken)
        );
        boosterFeeCollector = IBoosterFeeCollector(_echidnaStrategySettings.boosterFeeCollector);
    }

    function updateBoosterFeeCollector(address _collector) public onlyOwner {
        boosterFeeCollector = IBoosterFeeCollector(_collector);
    }

    function _depositToStakingContract(uint256 _amount, uint256) internal override {
        uint256 depositFee = _calculateDepositFee(_amount);
        uint256 liquidity = PlatypusLibrary.depositTokenToAsset(address(platypusAsset), _amount, depositFee);
        depositToken.approve(address(platypusPool), _amount);
        platypusPool.deposit(address(depositToken), _amount, address(this), type(uint256).max);
        depositToken.approve(address(platypusPool), 0);
        IERC20(address(platypusAsset)).approve(address(echidnaBooster), liquidity);
        echidnaBooster.deposit(PID, liquidity, false, type(uint256).max);
        IERC20(address(platypusAsset)).approve(address(echidnaBooster), 0);
    }

    function _calculateDepositFee(uint256 amount) internal view override returns (uint256) {
        return PlatypusLibrary.calculateDepositFee(address(platypusPool), address(platypusAsset), amount);
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 _withdrawAmount) {
        uint256 lpBalance = _echidnaRewardPool().balanceOf(address(this));
        uint256 liquidity = (_amount * lpBalance) / totalDeposits();
        liquidity = liquidity > lpBalance ? lpBalance : liquidity;
        echidnaBooster.withdraw(PID, liquidity, false, false, 0, type(uint256).max);

        (uint256 expectedAmount, , ) = platypusPool.quotePotentialWithdraw(address(depositToken), liquidity);
        IERC20(address(platypusAsset)).approve(address(platypusPool), liquidity);
        _withdrawAmount = platypusPool.withdraw(
            address(depositToken),
            liquidity,
            expectedAmount,
            address(this),
            type(uint256).max
        );
        IERC20(address(platypusAsset)).approve(address(platypusPool), 0);
    }

    function _emergencyWithdraw() internal override {
        depositToken.approve(address(echidnaBooster), 0);
        uint256 lpBalance = _echidnaRewardPool().balanceOf(address(this));
        echidnaBooster.withdraw(PID, lpBalance, false, false, 0, type(uint256).max);
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        IEchidnaRewardPool echidnaRewardPool = _echidnaRewardPool();
        uint256 rewardCount = echidnaRewardPool.extraRewardsLength() + 1;
        Reward[] memory pendingRewards = new Reward[](rewardCount);
        (uint256 pendingPTP, uint256 boostFee) = _pendingPTP();
        pendingRewards[0] = Reward({reward: address(PTP), amount: pendingPTP - boostFee});
        for (uint256 i = 1; i < rewardCount; i++) {
            IEchidnaRewardPool extraRewardPool = IEchidnaRewardPool(echidnaRewardPool.extraRewards(i - 1));
            pendingRewards[i] = Reward({
                reward: extraRewardPool.rewardToken(),
                amount: extraRewardPool.earned(address(this))
            });
        }
        return pendingRewards;
    }

    function _getRewards() internal override {
        (, uint256 boostFee) = _pendingPTP();
        _echidnaRewardPool().getReward(address(this), true);
        PTP.safeTransfer(address(boosterFeeCollector), boostFee);
    }

    function _pendingPTP() internal view returns (uint256 _ptpAmount, uint256 _boostFee) {
        _ptpAmount = _echidnaRewardPool().earned(address(this));
        _boostFee = boosterFeeCollector.calculateBoostFee(address(this), _ptpAmount);
    }

    function totalDeposits() public view override returns (uint256) {
        uint256 assetBalance = _echidnaRewardPool().balanceOf(address(this));
        if (assetBalance == 0) return 0;
        (uint256 depositTokenBalance, uint256 fee, bool enoughCash) = platypusPool.quotePotentialWithdraw(
            address(depositToken),
            assetBalance
        );
        require(enoughCash, "EchidnaStrategy::This shouldn't happen");
        return depositTokenBalance + fee;
    }

    function _echidnaRewardPool() internal view returns (IEchidnaRewardPool) {
        (, , , address rewardPool, , ) = IEchidnaBooster(address(echidnaBooster)).pools(PID);
        return IEchidnaRewardPool(rewardPool);
    }
}
