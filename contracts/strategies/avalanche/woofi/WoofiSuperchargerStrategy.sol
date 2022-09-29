// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./../../VariableRewardsStrategy.sol";
import "./interfaces/IMasterChefWoo.sol";
import "./interfaces/IWooStakingVault.sol";
import "./interfaces/IWooSuperChargerVault.sol";

contract WoofiSuperchargerStrategy is VariableRewardsStrategy {
    uint256 public immutable PID;
    IMasterChefWoo public immutable wooChef;
    IWooStakingVault public immutable xWoo;
    address public immutable swapPairWavaxUnderlying;
    address public immutable underlyingAsset;

    address public constant WOOe = 0xaBC9547B534519fF73921b1FBA6E672b5f58D083;

    constructor(
        address _stakingContract,
        uint256 _pid,
        address _swapPairWavaxUnderlying,
        VariableRewardsStrategySettings memory _settings,
        StrategySettings memory _strategySettings
    ) VariableRewardsStrategy(_settings, _strategySettings) {
        wooChef = IMasterChefWoo(_stakingContract);
        xWoo = IWooStakingVault(wooChef.xWoo());
        underlyingAsset = IWooSuperChargerVault(_strategySettings.depositToken).want();
        PID = _pid;
        swapPairWavaxUnderlying = _swapPairWavaxUnderlying;
    }

    receive() external payable {
        require(underlyingAsset == address(WAVAX) && msg.sender == address(WAVAX), "not allowed");
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
        pendingRewards[0] = Reward({reward: address(WOOe), amount: pendingWooAmount - instantWithdrawFee});

        return pendingRewards;
    }

    function _getRewards() internal override {
        wooChef.harvest(PID);
        xWoo.instantWithdraw(xWoo.balanceOf(address(this)));
    }

    function _convertRewardTokenToDepositToken(uint256 _fromAmount) internal override returns (uint256 toAmount) {
        if (underlyingAsset != address(rewardToken)) {
            _fromAmount = DexLibrary.swap(
                _fromAmount,
                address(rewardToken),
                underlyingAsset,
                IPair(swapPairWavaxUnderlying)
            );
        }

        if (underlyingAsset == address(WAVAX)) {
            WAVAX.withdraw(_fromAmount);
            IWooSuperChargerVault(address(depositToken)).deposit{value: _fromAmount}(_fromAmount);
        } else {
            IERC20(underlyingAsset).approve(address(depositToken), _fromAmount);
            IWooSuperChargerVault(address(depositToken)).deposit(_fromAmount);
        }

        return (_fromAmount * 1e18) / IWooSuperChargerVault(address(depositToken)).getPricePerFullShare();
    }

    function totalDeposits() public view override returns (uint256 amount) {
        (amount, ) = wooChef.userInfo(PID, address(this));
    }

    function _emergencyWithdraw() internal override {
        depositToken.approve(address(wooChef), 0);
        wooChef.emergencyWithdraw(PID);
    }
}
