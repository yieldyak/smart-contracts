// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./../../VariableRewardsStrategy.sol";
import "./interfaces/IMasterChefWoo.sol";
import "./interfaces/IWooStakingVault.sol";
import "./interfaces/IWooSuperChargerVault.sol";
import "./interfaces/IWooPPV2.sol";
import "./interfaces/IWooRouterV2.sol";

contract WoofiSuperchargerStrategy is VariableRewardsStrategy {
    using SafeERC20 for IERC20;

    uint256 public immutable PID;
    IMasterChefWoo public immutable wooChef;
    IWooStakingVault public immutable xWoo;
    IWooPPV2 public immutable pool;
    IWooRouterV2 public immutable router;
    address public immutable rebateCollector;

    address public constant WOOe = 0xaBC9547B534519fF73921b1FBA6E672b5f58D083;

    constructor(
        address _stakingContract,
        uint256 _pid,
        address _router,
        address _rebateCollector,
        VariableRewardsStrategySettings memory _settings,
        StrategySettings memory _strategySettings
    ) VariableRewardsStrategy(_settings, _strategySettings) {
        wooChef = IMasterChefWoo(_stakingContract);
        xWoo = IWooStakingVault(wooChef.xWoo());
        require(
            address(rewardToken) == IWooSuperChargerVault(_strategySettings.depositToken).want(),
            "Invalid reward token"
        );
        router = IWooRouterV2(_router);
        pool = IWooPPV2(router.wooPool());
        rebateCollector = _rebateCollector;
        PID = _pid;
    }

    receive() external payable {
        require(address(rewardToken) == address(WAVAX) && msg.sender == address(WAVAX), "not allowed");
    }

    function _depositToStakingContract(uint256 _amount, uint256) internal override {
        depositToken.approve(address(wooChef), _amount);
        wooChef.deposit(PID, _amount);
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 withdrawAmount) {
        wooChef.withdraw(PID, _amount);
        return _amount;
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        (, uint256 pendingWooAmount) = wooChef.pendingXWoo(PID, address(this));

        uint256 instantWithdrawFee = (pendingWooAmount * xWoo.withdrawFee()) / _bip();

        Reward[] memory pendingRewards = new Reward[](1);
        pendingRewards[0] = Reward({
            reward: address(rewardToken),
            amount: router.querySwap(WOOe, address(rewardToken), pendingWooAmount - instantWithdrawFee)
        });

        return pendingRewards;
    }

    function _getRewards() internal override {
        wooChef.harvest(PID);
        xWoo.instantWithdraw(xWoo.balanceOf(address(this)));
        uint256 amount = IERC20(WOOe).balanceOf(address(this));
        uint256 amountTo = pool.query(WOOe, address(rewardToken), amount);
        IERC20(WOOe).safeTransfer(address(pool), amount);
        IWooPPV2(pool).swap(WOOe, address(rewardToken), amount, amountTo, address(this), rebateCollector);
    }

    function _convertRewardTokenToDepositToken(uint256 _fromAmount) internal override returns (uint256 toAmount) {
        if (address(rewardToken) == address(WAVAX)) {
            WAVAX.withdraw(_fromAmount);
            IWooSuperChargerVault(address(depositToken)).deposit{value: _fromAmount}(_fromAmount);
        } else {
            rewardToken.approve(address(depositToken), _fromAmount);
            IWooSuperChargerVault(address(depositToken)).deposit(_fromAmount);
        }

        return depositToken.balanceOf(address(this));
    }

    function totalDeposits() public view override returns (uint256 amount) {
        (amount, ) = wooChef.userInfo(PID, address(this));
    }

    function _emergencyWithdraw() internal override {
        depositToken.approve(address(wooChef), 0);
        wooChef.emergencyWithdraw(PID);
    }
}
