// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity 0.7.3;

import "../interfaces/IERC20.sol";
import "../interfaces/IPair.sol";
import "../interfaces/IStakeDaoVault.sol";
import "../interfaces/IStakeDaoRewarder.sol";
import "../interfaces/IStakeDaoController.sol";
import "../interfaces/IStakeDaoStrategy.sol";
import "../lib/DexLibrary.sol";
import "../lib/CurveSwap.sol";
import "./MasterChefStrategy.sol";

contract StakeDaoStrategyForLP is MasterChefStrategy {
    using SafeMath for uint256;

    IWAVAX private constant WAVAX = IWAVAX(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);

    CurveSwap.Settings private zapSettings;
    IStakeDaoVault public stakeDaoVault;
    IStakeDaoRewarder public stakeDaoRewarder;

    constructor(
        string memory _name,
        address _depositToken,
        address _stakeDaoVault,
        address _stakeDaoRewarder,
        CurveSwap.Settings memory _curveSwapSettings,
        address _timelock,
        StrategySettings memory _strategySettings
    )
        MasterChefStrategy(
            _name,
            _depositToken,
            address(WAVAX), /*rewardToken=*/
            address(WAVAX),
            address(0),
            address(0),
            _timelock,
            0,
            _strategySettings
        )
    {
        stakeDaoVault = IStakeDaoVault(_stakeDaoVault);
        stakeDaoRewarder = IStakeDaoRewarder(_stakeDaoRewarder);
        zapSettings = _curveSwapSettings;
        IERC20(zapSettings.zapToken).approve(zapSettings.zapContract, type(uint256).max);
    }

    function _getDepositFeeBips(
        uint256 /* pid */
    ) internal pure override returns (uint256) {
        return 0;
    }

    function _getWithdrawFeeBips(
        uint256 /* pid */
    ) internal view override returns (uint256) {
        IStakeDaoController stakeDaoController = IStakeDaoController(stakeDaoVault.controller());
        IStakeDaoStrategy stakeDaoStrategy = IStakeDaoStrategy(stakeDaoController.strategies(address(depositToken)));
        return stakeDaoStrategy.withdrawalFee();
    }

    function setMaxSlippageBips(uint256 _maxSlippageBips) external onlyDev {
        zapSettings.maxSlippage = _maxSlippageBips;
    }

    function _depositTokensToStakeDaoShares(uint256 _amount) private returns (uint256 shares) {
        if (stakeDaoVault.totalSupply() == 0) {
            shares = _amount;
        } else {
            shares = (_amount.mul(stakeDaoVault.totalSupply())).div(stakeDaoVault.balance());
        }
    }

    function _depositToVault(uint256 _amount) private returns (uint256) {
        uint256 shares = _depositTokensToStakeDaoShares(_amount);
        depositToken.approve(address(stakeDaoVault), _amount);
        stakeDaoVault.deposit(_amount);
        depositToken.approve(address(stakeDaoVault), 0);
        return shares;
    }

    function _depositToRewarder(uint256 _sharesAmount) private {
        IERC20(address(stakeDaoVault)).approve(address(stakeDaoRewarder), _sharesAmount);
        stakeDaoRewarder.stake(_sharesAmount);
        IERC20(address(stakeDaoVault)).approve(address(stakeDaoRewarder), 0);
    }

    function _depositMasterchef(uint256 _pid, uint256 _amount) internal override {
        uint256 shares = _depositToVault(_amount);
        _depositToRewarder(shares);
    }

    function _withdrawMasterchef(uint256 _pid, uint256 _amount) internal override {
        uint256 shares = _depositTokensToStakeDaoShares(_amount);
        stakeDaoRewarder.withdraw(shares);
        stakeDaoVault.withdraw(shares);
    }

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
        uint256 pendingReward = stakeDaoRewarder.earned(address(_user), address(WAVAX));
        return (pendingReward, 0, address(0));
    }

    function _getRewards(uint256 _pid) internal override {
        stakeDaoRewarder.getReward();
    }

    function _getDepositBalance(uint256 pid, address user) internal view override returns (uint256 amount) {
        uint256 balance = stakeDaoRewarder.balanceOf(user);
        return (stakeDaoVault.balance().mul(balance)).div(stakeDaoVault.totalSupply());
    }

    function _bip() internal pure override returns (uint256) {
        return 10000;
    }

    function _convertRewardTokenToDepositToken(uint256 fromAmount) internal override returns (uint256 toAmount) {
        return CurveSwap.zapToAaveLP(fromAmount, address(rewardToken), address(0), zapSettings);
    }

    function _emergencyWithdraw(uint256 _pid) internal override {
        stakeDaoRewarder.exit();
        stakeDaoVault.withdrawAll();
    }
}
