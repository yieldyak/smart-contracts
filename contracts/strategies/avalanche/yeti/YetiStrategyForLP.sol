// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../VariableRewardsStrategy.sol";
import "../../../lib/SafeERC20.sol";
import "../curve/lib/CurveSwap.sol";

import "./interfaces/IYetiVoterProxy.sol";

contract YetiStrategyForLP is VariableRewardsStrategy {
    using SafeERC20 for IERC20;

    address private constant YETI = 0x77777777777d4554c39223C354A05825b2E8Faa3;

    address public stakingContract;
    IYetiVoterProxy public proxy;

    CurveSwap.Settings private zapSettings;

    constructor(
        CurveSwap.Settings memory _zapSettings,
        address _stakingContract,
        address _voterProxy,
        VariableRewardsStrategySettings memory _settings,
        StrategySettings memory _strategySettings
    ) VariableRewardsStrategy(_settings, _strategySettings) {
        stakingContract = _stakingContract;
        proxy = IYetiVoterProxy(_voterProxy);
        zapSettings = _zapSettings;
    }

    function _depositToStakingContract(uint256 _amount) internal override {
        depositToken.safeTransfer(address(proxy), _amount);
        proxy.deposit(stakingContract, address(depositToken), _amount);
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 _withdrawAmount) {
        proxy.withdraw(stakingContract, address(depositToken), _amount);
        return _amount;
    }

    function _emergencyWithdraw() internal override {
        depositToken.approve(address(proxy), 0);
        proxy.emergencyWithdraw(stakingContract, address(depositToken));
    }

    /**
     * @notice Returns pending rewards
     */
    function _pendingRewards() internal view override returns (Reward[] memory) {
        Reward[] memory pendingRewards = new Reward[](1);
        uint256 pendingYETI = proxy.pendingRewards(stakingContract);
        pendingRewards[0] = Reward({reward: address(YETI), amount: pendingYETI});
        return pendingRewards;
    }

    function _getRewards() internal override {
        proxy.claimReward(stakingContract);
    }

    function _convertRewardTokenToDepositToken(uint256 _fromAmount) internal override returns (uint256 toAmount) {
        return
            CurveSwap.zapToFactory3AssetsPoolLP(_fromAmount, address(rewardToken), address(depositToken), zapSettings);
    }

    function totalDeposits() public view override returns (uint256) {
        return proxy.poolBalance(stakingContract);
    }
}
