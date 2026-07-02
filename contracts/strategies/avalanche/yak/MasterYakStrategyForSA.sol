// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../BaseStrategy.sol";
import "../../../interfaces/IPair.sol";
import "../../../lib/DexLibrary.sol";

import "./interfaces/IYakChef.sol";

/**
 * @notice Strategy for Master Yak, which pays rewards in AVAX
 * @dev Fees are paid in WAVAX
 */
contract MasterYakStrategyForSA is BaseStrategy {
    IYakChef public stakingContract;
    IPair private swapPairToken;
    uint256 public PID;

    constructor(
        address _stakingContract,
        address _swapPairToken,
        uint256 pid,
        BaseStrategySettings memory _baseStrategySettings,
        StrategySettings memory _strategySettings
    ) BaseStrategy(_baseStrategySettings, _strategySettings) {
        stakingContract = IYakChef(_stakingContract);
        swapPairToken = IPair(_swapPairToken);
        PID = pid;
    }

    receive() external payable {}

    function _depositToStakingContract(uint256 _amount, uint256 _depositFee) internal override {
        uint256 amount = _amount - _depositFee;
        depositToken.approve(address(stakingContract), amount);
        stakingContract.deposit(PID, amount);
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 withdrawAmount) {
        stakingContract.withdraw(PID, _amount);
        return _amount;
    }

    function _emergencyWithdraw() internal override {
        stakingContract.emergencyWithdraw(PID);
        depositToken.approve(address(stakingContract), 0);
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        Reward[] memory pendingRewards = new Reward[](1);
        pendingRewards[0] = Reward({reward: address(WGAS), amount: stakingContract.pendingRewards(PID, address(this))});
        return pendingRewards;
    }

    function _getRewards() internal override {
        stakingContract.deposit(PID, 0);
        uint256 balance = address(this).balance;
        if (balance > 0) {
            WGAS.deposit{value: balance}();
        }
    }

    function _convertRewardTokenToDepositToken(uint256 _fromAmount) internal override returns (uint256 toAmount) {
        if (_fromAmount == 0) return 0;
        return DexLibrary.swap(_fromAmount, address(rewardToken), address(depositToken), swapPairToken);
    }

    function totalDeposits() public view override returns (uint256) {
        (uint256 amount, ) = stakingContract.userInfo(PID, address(this));
        return amount;
    }
}
