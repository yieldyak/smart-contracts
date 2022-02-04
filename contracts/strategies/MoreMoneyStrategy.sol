// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity 0.7.3;

import "../interfaces/IERC20.sol";
import "../interfaces/IPair.sol";
import "../interfaces/IMoreMoneyStakingRewards.sol";
import "../lib/DexLibrary.sol";
import "../lib/CurveSwap.sol";
import "./MasterChefStrategy.sol";

contract MoreMoneyStrategy is MasterChefStrategy {
    using SafeMath for uint256;

    IWAVAX private constant WAVAX = IWAVAX(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);

    CurveSwap.Settings private zapSettings;
    address private curvePool;
    IMoreMoneyStakingRewards public stakingContract;

    constructor(
        string memory _name,
        address _depositToken,
        address _poolRewardToken,
        address _swapPairPoolReward,
        address _stakingContract,
        CurveSwap.Settings memory _curveSwapSettings,
        address _timelock,
        StrategySettings memory _strategySettings
    )
        MasterChefStrategy(
            _name,
            _depositToken,
            address(WAVAX), /*rewardToken=*/
            _poolRewardToken,
            _swapPairPoolReward,
            address(0),
            address(0),
            _timelock,
            0,
            _strategySettings
        )
    {
        stakingContract = IMoreMoneyStakingRewards(_stakingContract);
        curvePool = _depositToken;
        zapSettings = _curveSwapSettings;
        IERC20(zapSettings.zapToken).approve(zapSettings.zapContract, type(uint256).max);
    }

    function setMaxSlippageBips(uint256 _maxSlippageBips) external onlyDev {
        zapSettings.maxSlippage = _maxSlippageBips;
    }

    function _depositMasterchef(
        uint256, /*pid*/
        uint256 _amount
    ) internal override {
        depositToken.approve(address(stakingContract), _amount);
        stakingContract.stake(_amount);
        depositToken.approve(address(stakingContract), 0);
    }

    function _withdrawMasterchef(
        uint256, /*pid*/
        uint256 _amount
    ) internal override {
        stakingContract.withdraw(_amount);
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        if (a >= b) {
            return b;
        } else {
            return a;
        }
    }

    function _earned(address account) private view returns (uint256) {
        return
            (
                stakingContract.balanceOf(account).mul(
                    (stakingContract.rewardPerToken() - stakingContract.userRewardPerTokenAccountedFor(account))
                )
            ).div(1e18);
    }

    function _calculateReward(address account) private view returns (uint256) {
        uint256 vStart = stakingContract.vestingStart(account);
        uint256 timeDelta = block.timestamp - vStart;
        uint256 totalRewards = stakingContract.rewards(account).add(_earned(account));

        if (stakingContract.vestingPeriod() == 0) {
            return totalRewards;
        } else {
            uint256 rewardVested = vStart > 0 && timeDelta > 0
                ? _min(totalRewards, (totalRewards * timeDelta) / stakingContract.vestingPeriod())
                : 0;
            return rewardVested;
        }
    }

    function _pendingRewards(
        uint256, /*pid*/
        address _user
    )
        internal
        view
        override
        returns (
            uint256,
            uint256,
            address
        )
    {
        uint256 pendingReward = _calculateReward(_user);
        return (pendingReward, 0, address(0));
    }

    function _getRewards(
        uint256 /*_pid*/
    ) internal override {
        stakingContract.withdrawVestedReward();
    }

    function _getDepositBalance(
        uint256, /*pid*/
        address user
    ) internal view override returns (uint256 amount) {
        return stakingContract.balanceOf(user);
    }

    function _bip() internal pure override returns (uint256) {
        return 10000;
    }

    function _convertRewardTokenToDepositToken(uint256 fromAmount) internal override returns (uint256 toAmount) {
        return
            CurveSwap.zapToFactory4AssetsPoolLP(fromAmount, address(rewardToken), address(depositToken), zapSettings);
    }

    function _emergencyWithdraw(
        uint256 /*pid*/
    ) internal override {
        stakingContract.exit();
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
}
