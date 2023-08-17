// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../BaseStrategy.sol";

import "./interfaces/ISynapseSwap.sol";
import "./interfaces/IMiniChefV2.sol";

contract SynapseStrategy is BaseStrategy {
    using SafeERC20 for IERC20;

    address private immutable SYN;

    uint256 public immutable PID;
    IMiniChefV2 public immutable miniChef;

    ISynapseSwap public immutable synapseSwap;
    address public immutable synapseLpTokenIn;
    uint256 public immutable synapseLpTokenIndex;
    uint256 public immutable synapseLpTokenCount;

    struct SynapseStrategySettings {
        address stakingContract;
        uint256 pid;
        address synapseLpTokenIn;
        address synapseSwap;
        uint256 synapseLpTokenCount;
    }

    constructor(
        SynapseStrategySettings memory _synapseStrategySettings,
        BaseStrategySettings memory _settings,
        StrategySettings memory _strategySettings
    ) BaseStrategy(_settings, _strategySettings) {
        PID = _synapseStrategySettings.pid;
        miniChef = IMiniChefV2(_synapseStrategySettings.stakingContract);
        SYN = miniChef.SYNAPSE();
        synapseLpTokenIn = _synapseStrategySettings.synapseLpTokenIn;
        synapseSwap = ISynapseSwap(_synapseStrategySettings.synapseSwap);
        synapseLpTokenCount = _synapseStrategySettings.synapseLpTokenCount;
        synapseLpTokenIndex = synapseSwap.getTokenIndex(synapseLpTokenIn);
    }

    function _depositToStakingContract(uint256 _amount, uint256) internal override {
        IERC20(address(depositToken)).approve(address(miniChef), _amount);
        miniChef.deposit(PID, _amount, address(this));
        IERC20(address(depositToken)).approve(address(miniChef), 0);
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 _withdrawAmount) {
        miniChef.withdraw(PID, _amount, address(this));
        return _amount;
    }

    function _emergencyWithdraw() internal override {
        depositToken.approve(address(miniChef), 0);
        miniChef.emergencyWithdraw(PID, address(this));
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        Reward[] memory pendingRewards = new Reward[](1);
        uint256 pendingSYN = miniChef.pendingSynapse(PID, address(this));
        pendingRewards[0] = Reward({reward: address(SYN), amount: pendingSYN});
        return pendingRewards;
    }

    function _getRewards() internal override {
        miniChef.harvest(PID, address(this));
    }

    function totalDeposits() public view override returns (uint256) {
        (uint256 amount,) = miniChef.userInfo(PID, address(this));
        return amount;
    }

    function _convertRewardTokenToDepositToken(uint256 _fromAmount) internal override returns (uint256 toAmount) {
        if (synapseLpTokenIn != address(rewardToken)) {
            FormattedOffer memory offer = simpleRouter.query(_fromAmount, address(rewardToken), synapseLpTokenIn);
            _fromAmount = _swap(offer);
        }

        IERC20(synapseLpTokenIn).approve(address(synapseSwap), _fromAmount);
        uint256[] memory amounts = new uint256[](synapseLpTokenCount);
        amounts[synapseLpTokenIndex] = _fromAmount;
        toAmount = synapseSwap.addLiquidity(amounts, 0, type(uint256).max);
    }
}
