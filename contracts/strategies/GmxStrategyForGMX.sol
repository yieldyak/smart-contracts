// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity 0.7.3;

import "../interfaces/IGmxProxy.sol";
import "../interfaces/IGmxRewardRouter.sol";
import "../interfaces/IGmxRewardTracker.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IPair.sol";
import "../interfaces/IWAVAX.sol";
import "../lib/DexLibrary.sol";
import "../lib/SafeERC20.sol";
import "../lib/DSMath.sol";
import "./MasterChefStrategyForSA.sol";

contract GmxStrategyForGMX is MasterChefStrategyForSA {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IWAVAX private constant WAVAX = IWAVAX(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);
    address internal constant GMX = 0x62edc0692BD897D2295872a9FFCac5425011c661;

    IGmxProxy public proxy;

    constructor(
        string memory _name,
        address _depositToken,
        address _swapPairToken,
        address _gmxProxy,
        address _timelock,
        StrategySettings memory _strategySettings
    )
        MasterChefStrategyForSA(
            _name,
            _depositToken,
            address(WAVAX), /*rewardToken=*/
            address(WAVAX),
            _swapPairToken,
            address(0),
            _swapPairToken,
            _timelock,
            0,
            _strategySettings
        )
    {
        proxy = IGmxProxy(_gmxProxy);
    }

    function setProxy(address _proxy) external onlyOwner {
        proxy = IGmxProxy(_proxy);
    }

    function _depositMasterchef(
        uint256, /*_pid*/
        uint256 _amount
    ) internal override {
        depositToken.safeTransfer(address(proxy), _amount);
        proxy.stakeGmx(_amount);
    }

    function _withdrawMasterchef(
        uint256, /*_pid*/
        uint256 _amount
    ) internal override {
        proxy.withdrawGmx(_amount);
    }

    function _pendingRewards(
        uint256, /*_pid*/
        address /*_user*/
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
        uint256 pendingReward = IGmxRewardTracker(_rewardTracker()).claimable(_depositor());
        return (pendingReward, 0, address(0));
    }

    function _getRewards(
        uint256 /*_pid*/
    ) internal override {
        proxy.claimReward(_rewardTracker());
    }

    function _getDepositBalance(
        uint256, /*_pid*/
        address /*user*/
    ) internal view override returns (uint256) {
        return _gmxDepositBalance();
    }

    function _emergencyWithdraw(
        uint256 /*_pid*/
    ) internal override {
        uint256 balance = _gmxDepositBalance();
        proxy.emergencyWithdrawGMX(balance);
    }

    function _gmxDepositBalance() private view returns (uint256) {
        return IGmxRewardTracker(_rewardTracker()).stakedAmounts(_depositor());
    }

    function _depositor() private view returns (address) {
        return proxy.gmxDepositor();
    }

    function _rewardTracker() private view returns (address) {
        address gmxRewardRouter = proxy.gmxRewardRouter();
        return IGmxRewardRouter(gmxRewardRouter).feeGmxTracker();
    }

    function _getDepositFeeBips(
        uint256 /*_pid*/
    ) internal pure override returns (uint256) {
        return 0;
    }

    function _getWithdrawFeeBips(
        uint256 /*_pid*/
    ) internal pure override returns (uint256) {
        return 0;
    }

    function _bip() internal pure override returns (uint256) {
        return 10000;
    }
}
