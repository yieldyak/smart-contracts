// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../VariableRewardsStrategy.sol";
import "../../interfaces/IERC20.sol";
import "../../interfaces/IPair.sol";
import "../../lib/DexLibrary.sol";
import "../curve/lib/CurveSwap.sol";

import "./interfaces/IStargateLPStaking.sol";
import "./interfaces/IStargateRouter.sol";

contract StargateStrategyForLP is VariableRewardsStrategy {
    address private constant STARGATE = 0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590;

    struct StakingSettings {
        address stakingContract;
        uint256 pid;
        address stargateRouter;
        uint256 routerPid;
    }

    address private immutable underlyingToken;
    address private immutable swapPairRewardTokenUnderlying;

    IStargateLPStaking public stakingContract;
    uint256 public immutable PID;
    IStargateRouter public stargateRouter;
    uint256 public immutable routerPid;

    constructor(
        StakingSettings memory _stakingSettings,
        address _underlyingToken,
        address _swapPairRewardTokenUnderlying,
        RewardSwapPairs[] memory _rewardSwapPairs,
        BaseSettings memory _baseSettings,
        StrategySettings memory _strategySettings
    ) VariableRewardsStrategy(_rewardSwapPairs, _baseSettings, _strategySettings) {
        stakingContract = IStargateLPStaking(_stakingSettings.stakingContract);
        stargateRouter = IStargateRouter(_stakingSettings.stargateRouter);
        underlyingToken = _underlyingToken;
        swapPairRewardTokenUnderlying = _swapPairRewardTokenUnderlying;
        routerPid = _stakingSettings.routerPid;
        PID = _stakingSettings.pid;
    }

    function _depositToStakingContract(uint256 _amount) internal override {
        IERC20(asset).approve(address(stakingContract), _amount);
        stakingContract.deposit(PID, _amount);
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 _withdrawAmount) {
        stakingContract.withdraw(PID, _amount);
        return _amount;
    }

    function _emergencyWithdraw() internal override {
        IERC20(asset).approve(address(stakingContract), 0);
        stakingContract.emergencyWithdraw(PID);
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        uint256 pendingStargate = stakingContract.pendingStargate(PID, address(this));
        Reward[] memory pendingRewards = new Reward[](1);

        pendingRewards[0] = Reward({reward: STARGATE, amount: pendingStargate});
        return pendingRewards;
    }

    function _getRewards() internal override {
        stakingContract.deposit(PID, 0);
    }

    function totalAssets() public view override returns (uint256) {
        (uint256 amount, ) = stakingContract.userInfo(PID, address(this));
        return amount;
    }

    function _convertRewardTokenToDepositToken(uint256 fromAmount) internal override returns (uint256 toAmount) {
        uint256 amount = DexLibrary.swap(
            fromAmount,
            address(WAVAX),
            underlyingToken,
            IPair(swapPairRewardTokenUnderlying)
        );
        uint256 balanceBefore = IERC20(asset).balanceOf(address(this));

        IERC20(underlyingToken).approve(address(stargateRouter), amount);
        stargateRouter.addLiquidity(routerPid, amount, address(this));
        IERC20(underlyingToken).approve(address(stargateRouter), 0);

        toAmount = IERC20(asset).balanceOf(address(this)) - balanceBefore;
    }
}
