// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../../VariableRewardsStrategy.sol";
import "../../../lib/SafeERC20.sol";

import "./interfaces/IEchidnaVoterProxy.sol";

contract EchidnaStrategyForLP is VariableRewardsStrategy {
    using SafeERC20 for IERC20;

    address private constant ECD = 0xeb8343D5284CaEc921F035207ca94DB6BAaaCBcd;
    address private constant PTP = 0x22d4002028f537599bE9f666d1c4Fa138522f9c8;

    address public stakingContract;
    IEchidnaVoterProxy public proxy;
    address public swapPairWavaxPtp;
    uint256 public immutable PID;

    constructor(
        string memory _name,
        address _depositToken,
        address _swapPairWavaxPtp,
        RewardSwapPairs[] memory _rewardSwapPairs,
        address _stakingContract,
        uint256 _pid,
        address _voterProxy,
        address _timelock,
        StrategySettings memory _strategySettings
    ) VariableRewardsStrategy(_name, _depositToken, _rewardSwapPairs, _timelock, _strategySettings) {
        stakingContract = _stakingContract;
        PID = _pid;
        proxy = IEchidnaVoterProxy(_voterProxy);
        swapPairWavaxPtp = _swapPairWavaxPtp;
    }

    function _depositToStakingContract(uint256 _amount) internal override {
        depositToken.safeTransfer(address(proxy), _amount);
        proxy.deposit(PID, stakingContract, address(depositToken), _amount);
        proxy.distributeReward(stakingContract, PID);
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 _withdrawAmount) {
        proxy.withdraw(PID, stakingContract, address(depositToken), _amount);
        proxy.distributeReward(stakingContract, PID);
        return _amount;
    }

    function _emergencyWithdraw() internal override {
        depositToken.approve(address(proxy), 0);
        proxy.emergencyWithdraw(PID, stakingContract, address(depositToken));
    }

    /**
     * @notice Returns pending rewards
     * @dev `rewarder` distributions are not considered
     */
    function _pendingRewards() internal view override returns (Reward[] memory) {
        Reward[] memory pendingRewards = new Reward[](2);
        (uint256 pendingECD, uint256 pendingPTP) = proxy.pendingRewards(stakingContract, PID);
        pendingRewards[0] = Reward({reward: address(ECD), amount: pendingECD});
        pendingRewards[1] = Reward({reward: address(PTP), amount: pendingPTP});
        return pendingRewards;
    }

    function _getRewards() internal override {
        proxy.claimReward(stakingContract, PID);
    }

    function _convertRewardTokenToDepositToken(uint256 _fromAmount) internal override returns (uint256 toAmount) {
        uint256 ptpAmount = DexLibrary.swap(_fromAmount, address(rewardToken), PTP, IPair(swapPairWavaxPtp));

        return
            DexLibrary.convertRewardTokensToDepositTokens(
                ptpAmount,
                PTP,
                address(depositToken),
                IPair(address(depositToken)),
                IPair(address(depositToken))
            );
    }

    function totalDeposits() public view override returns (uint256) {
        return proxy.poolBalance(stakingContract, PID);
    }
}
