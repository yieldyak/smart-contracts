// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../../VariableRewardsStrategy.sol";

import "./interfaces/ILevelMasterV2.sol";
import "./interfaces/ILevelPool.sol";

contract LevelStrategy is VariableRewardsStrategy {
    address private constant LVL = 0xB64E280e9D1B5DbEc4AcceDb2257A87b400DB149;

    ILevelMasterV2 public immutable levelMaster;
    ILevelPool public immutable levelPool;
    uint256 public immutable PID;

    address lpTokenIn;
    address pairLpTokenIn;
    uint256 feePairLpTokenIn;

    constructor(
        address _stakingContract,
        uint256 _pid,
        address _pairLpTokenIn,
        uint256 _feePairLpTokenIn,
        VariableRewardsStrategySettings memory _variableRewardsStrategySettings,
        StrategySettings memory _strategySettings
    ) VariableRewardsStrategy(_variableRewardsStrategySettings, _strategySettings) {
        PID = _pid;
        levelMaster = ILevelMasterV2(_stakingContract);
        levelPool = ILevelPool(levelMaster.levelPool());
        _updateLPTokenIn(_pairLpTokenIn, _feePairLpTokenIn);
    }

    function updateLPTokenIn(address _pair, uint256 _swapFee) external onlyDev {
        _updateLPTokenIn(_pair, _swapFee);
    }

    function _updateLPTokenIn(address _pair, uint256 _swapFee) private {
        if (_pair != address(0)) {
            address token0 = IPair(_pair).token0();
            address token1 = IPair(_pair).token1();
            require(token0 == address(rewardToken) || token1 == address(rewardToken), "LevelStrategy::Invalid pair");
            lpTokenIn = token0 == address(rewardToken) ? token1 : token0;
            pairLpTokenIn = _pair;
            feePairLpTokenIn = _swapFee;
        } else {
            lpTokenIn = address(0);
            pairLpTokenIn = address(0);
            feePairLpTokenIn = 0;
        }
    }

    function _depositToStakingContract(uint256 _amount, uint256) internal override {
        depositToken.approve(address(levelMaster), _amount);
        levelMaster.deposit(PID, _amount, address(this));
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 _withdrawAmount) {
        levelMaster.withdraw(PID, _amount, address(this));
        _withdrawAmount = _amount;
    }

    function _emergencyWithdraw() internal override {
        levelMaster.withdraw(PID, totalDeposits(), address(this));
        depositToken.approve(address(levelMaster), 0);
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        uint256 pendingReward = levelMaster.pendingReward(PID, address(this));
        Reward[] memory pendingRewards = new Reward[](1);
        pendingRewards[0] = Reward({reward: LVL, amount: pendingReward});
        return pendingRewards;
    }

    function _getRewards() internal override {
        levelMaster.harvest(PID, address(this));
    }

    function _convertRewardTokenToDepositToken(uint256 fromAmount) internal override returns (uint256 toAmount) {
        address tokenIn = lpTokenIn;
        if (tokenIn > address(0)) {
            fromAmount =
                DexLibrary.swap(fromAmount, address(rewardToken), tokenIn, IPair(pairLpTokenIn), feePairLpTokenIn);
        } else {
            tokenIn = address(rewardToken);
        }
        uint256 before = depositToken.balanceOf(address(this));
        IERC20(tokenIn).approve(address(levelPool), fromAmount);
        levelPool.addLiquidity(address(depositToken), tokenIn, fromAmount, 0, address(this));
        return depositToken.balanceOf(address(this)) - before;
    }

    function totalDeposits() public view override returns (uint256) {
        (uint256 amount,) = levelMaster.userInfo(PID, address(this));
        return amount;
    }
}
