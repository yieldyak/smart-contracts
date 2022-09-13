// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./../../VariableRewardsStrategy.sol";

import "./interfaces/IMasterPlatypus.sol";
import "./interfaces/IPlatypusPool.sol";
import "./interfaces/IPlatypusVoterProxy.sol";
import "./interfaces/IPlatypusAsset.sol";
import "./lib/PlatypusLibrary.sol";

contract PlatypusStrategy is VariableRewardsStrategy {
    using SafeERC20 for IERC20;

    struct PlatypusStrategySettings {
        address pool;
        address swapPairToken;
        uint256 pid;
        uint256 maxSlippage;
        address voterProxy;
    }

    address public constant PTP = 0x22d4002028f537599bE9f666d1c4Fa138522f9c8;

    IPlatypusAsset public immutable asset;
    IPlatypusPool public immutable pool;
    IPlatypusVoterProxy public proxy;

    uint256 public immutable PID;
    uint256 public maxSlippage;
    address public immutable swapPairToken;

    constructor(
        PlatypusStrategySettings memory _platypusStrategySettings,
        VariableRewardsStrategySettings memory _variableRewardsStrategySettings,
        StrategySettings memory _strategySettings
    ) VariableRewardsStrategy(_variableRewardsStrategySettings, _strategySettings) {
        PID = _platypusStrategySettings.pid;

        pool = IPlatypusPool(_platypusStrategySettings.pool);
        asset = IPlatypusAsset(pool.assetOf(_strategySettings.depositToken));
        proxy = IPlatypusVoterProxy(_platypusStrategySettings.voterProxy);
        maxSlippage = _platypusStrategySettings.maxSlippage;
        swapPairToken = _platypusStrategySettings.swapPairToken;
    }

    function setPlatypusVoterProxy(address _voterProxy) external onlyOwner {
        proxy = IPlatypusVoterProxy(_voterProxy);
    }

    /**
     * @notice Update max slippage for withdrawal
     * @dev Function name matches interface for FeeCollector
     */
    function updateMaxSwapSlippage(uint256 slippageBips) public onlyDev {
        maxSlippage = slippageBips;
    }

    function _calculateDepositFee(uint256 amount) internal view override returns (uint256) {
        return PlatypusLibrary.calculateDepositFee(address(pool), address(asset), amount);
    }

    function _depositToStakingContract(uint256 _amount, uint256 _depositFee) internal override {
        depositToken.safeTransfer(address(proxy), _amount);
        proxy.deposit(PID, address(0), address(pool), address(depositToken), address(asset), _amount, _depositFee);
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 withdrawAmount) {
        proxy.claimReward(address(0), PID);
        return
            proxy.withdraw(PID, address(0), address(pool), address(depositToken), address(asset), maxSlippage, _amount);
    }

    function _pendingRewards() internal view virtual override returns (Reward[] memory) {
        return proxy.pendingRewards(PID);
    }

    function _convertRewardTokenToDepositToken(uint256 _fromAmount)
        internal
        virtual
        override
        returns (uint256 toAmount)
    {
        if (rewardToken == depositToken) return _fromAmount;
        toAmount = DexLibrary.swap(_fromAmount, address(rewardToken), address(depositToken), IPair(swapPairToken));
    }

    function _getRewards() internal virtual override {
        proxy.claimReward(address(0), PID);
    }

    function totalDeposits() public view override returns (uint256) {
        uint256 depositBalance = proxy.poolBalance(address(0), PID);
        return depositBalance;
    }

    function _emergencyWithdraw() internal override {
        proxy.emergencyWithdraw(PID, address(0), address(pool), address(depositToken), address(asset));
    }
}
