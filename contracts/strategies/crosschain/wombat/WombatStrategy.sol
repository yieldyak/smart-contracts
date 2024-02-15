// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../BaseStrategy.sol";
import "./interfaces/IBoostedMasterWombat.sol";
import "./interfaces/IWombatPool.sol";
import "./interfaces/IWombatAsset.sol";
import "./interfaces/IWombatProxy.sol";

contract WombatStrategy is BaseStrategy {
    using SafeERC20 for IERC20;

    IWombatPool public immutable wombatPool;
    address public immutable masterWombat;
    uint256 public immutable pid;
    address public immutable underlyingToken;

    IWombatProxy public proxy;

    constructor(
        address _wombatPool,
        address _proxy,
        BaseStrategySettings memory baseStrategySettings,
        StrategySettings memory _strategySettings
    ) BaseStrategy(baseStrategySettings, _strategySettings) {
        wombatPool = IWombatPool(_wombatPool);
        masterWombat = wombatPool.masterWombat();
        pid = IBoostedMasterWombat(masterWombat).getAssetPid(address(depositToken));
        proxy = IWombatProxy(_proxy);
        underlyingToken = IWombatAsset(address(depositToken)).underlyingToken();
    }

    function setProxy(address _proxy) external onlyDev {
        proxy = IWombatProxy(_proxy);
    }

    function _depositToStakingContract(uint256 _amount, uint256) internal override {
        depositToken.transfer(proxy.voter(), _amount);
        proxy.depositToStakingContract(masterWombat, pid, address(depositToken), _amount);
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 _withdrawAmount) {
        proxy.withdrawFromStakingContract(masterWombat, pid, address(depositToken), _amount);
        return _amount;
    }

    function _emergencyWithdraw() internal override {
        proxy.emergencyWithdraw(masterWombat, pid, address(depositToken));
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        return proxy.pendingRewards(masterWombat, pid);
    }

    function _getRewards() internal override {
        proxy.getRewards(masterWombat, pid);
    }

    function _convertRewardTokenToDepositToken(uint256 _fromAmount) internal override returns (uint256) {
        if (address(rewardToken) != underlyingToken) {
            FormattedOffer memory offer = simpleRouter.query(_fromAmount, address(rewardToken), underlyingToken);
            _fromAmount = _swap(offer);
        }
        if (_fromAmount > 0) {
            IERC20(underlyingToken).approve(address(wombatPool), _fromAmount);
            wombatPool.deposit(underlyingToken, _fromAmount, 0, address(proxy.voter()), block.timestamp, true);
        }
        return 0;
    }

    function totalDeposits() public view override returns (uint256) {
        return proxy.totalDeposits(masterWombat, pid);
    }
}
