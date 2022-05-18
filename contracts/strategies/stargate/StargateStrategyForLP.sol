// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../MasterChefStrategy.sol";
import "../../interfaces/IERC20.sol";
import "../../interfaces/IPair.sol";
import "../../lib/DexLibrary.sol";
import "../curve/lib/CurveSwap.sol";

import "./interfaces/IStargateLPStaking.sol";
import "./interfaces/IStargateRouter.sol";

contract StargateStrategyForLP is MasterChefStrategy {
    using SafeMath for uint256;

    struct Tokens {
        address depositToken;
        address underlyingToken;
        address poolRewardToken;
    }

    address private constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    address private immutable underlyingToken;
    address private immutable swapPairRewardTokenUnderlying;
    uint256 private immutable routerPid;

    IStargateLPStaking public stakingContract;
    IStargateRouter public stargateRouter;

    constructor(
        string memory _name,
        Tokens memory _tokens,
        address _swapPairPoolReward,
        address _swapPairRewardTokenUnderlying,
        address _stakingContract,
        uint256 _pid,
        address _stargateRouter,
        uint256 _routerPid,
        address _timelock,
        StrategySettings memory _strategySettings
    )
        MasterChefStrategy(
            _name,
            _tokens.depositToken,
            WAVAX, /*rewardToken=*/
            _tokens.poolRewardToken,
            _swapPairPoolReward,
            address(0),
            _timelock,
            _pid,
            _strategySettings
        )
    {
        stakingContract = IStargateLPStaking(_stakingContract);
        stargateRouter = IStargateRouter(_stargateRouter);
        underlyingToken = _tokens.underlyingToken;
        swapPairRewardTokenUnderlying = _swapPairRewardTokenUnderlying;
        routerPid = _routerPid;
    }

    function _depositMasterchef(uint256 _pid, uint256 _amount) internal override {
        depositToken.approve(address(stakingContract), _amount);
        stakingContract.deposit(_pid, _amount);
    }

    function _withdrawMasterchef(uint256 _pid, uint256 _amount) internal override {
        stakingContract.withdraw(_pid, _amount);
    }

    function _emergencyWithdraw(uint256 _pid) internal override {
        depositToken.approve(address(stakingContract), 0);
        stakingContract.emergencyWithdraw(_pid);
    }

    /**
     * @notice Returns pending rewards
     * @dev `rewarder` distributions are not considered
     */
    function _pendingRewards(uint256 _pid, address _user)
        internal
        view
        override
        returns (
            uint256,
            uint256,
            address
        )
    {
        uint256 pendingStargate = stakingContract.pendingStargate(_pid, _user);
        return (pendingStargate, 0, address(0));
    }

    function _getRewards(uint256 _pid) internal override {
        stakingContract.deposit(_pid, 0);
    }

    function _getDepositBalance(uint256 _pid, address _user) internal view override returns (uint256 amount) {
        (amount, ) = stakingContract.userInfo(_pid, _user);
    }

    function _convertRewardTokenToDepositToken(uint256 fromAmount) internal override returns (uint256 toAmount) {
        uint256 amount = DexLibrary.swap(fromAmount, WAVAX, underlyingToken, IPair(swapPairRewardTokenUnderlying));
        uint256 balanceBefore = depositToken.balanceOf(address(this));

        IERC20(underlyingToken).approve(address(stargateRouter), amount);
        stargateRouter.addLiquidity(routerPid, amount, address(this));
        IERC20(underlyingToken).approve(address(stargateRouter), 0);

        toAmount = depositToken.balanceOf(address(this)).sub(balanceBefore);
    }

    function _getDepositFeeBips(
        uint256 /* pid */
    ) internal pure override returns (uint256) {
        return 0;
    }

    function _getWithdrawFeeBips(
        uint256 /* pid */
    ) internal pure override returns (uint256) {
        return 0;
    }

    function _bip() internal pure override returns (uint256) {
        return 10000;
    }
}
