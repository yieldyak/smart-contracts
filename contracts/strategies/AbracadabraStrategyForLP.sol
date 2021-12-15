// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity 0.7.3;

import "../interfaces/IAbracadabraChef.sol";
import "../lib/CurveSwap.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IPair.sol";
import "../lib/DexLibrary.sol";
import "./MasterChefStrategy.sol";

contract AbracadabraStrategyForLP is MasterChefStrategy {
    using SafeMath for uint256;

    IWAVAX private constant WAVAX = IWAVAX(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);

    IAbracadabraChef public abracadabraChef;
    CurveSwap.Settings private zapSettings;

    constructor(
        string memory _name,
        address _depositToken,
        address _poolRewardToken,
        address _swapPairPoolReward,
        address _swapPairExtraReward,
        address _stakingContract,
        CurveSwap.Settings memory _zapSettings,
        uint256 _pid,
        address _timelock,
        StrategySettings memory _strategySettings
    )
        MasterChefStrategy(
            _name,
            _depositToken,
            address(WAVAX), /*rewardToken=*/
            _poolRewardToken,
            _swapPairPoolReward,
            _swapPairExtraReward,
            _timelock,
            _pid,
            _strategySettings
        )
    {
        abracadabraChef = IAbracadabraChef(_stakingContract);
        require(_zapSettings.swapPairRewardZap > address(0), "Swap pair 0 is necessary but not supplied");
        require(
            IPair(_zapSettings.swapPairRewardZap).token0() == _zapSettings.zapToken ||
                IPair(_zapSettings.swapPairRewardZap).token1() == _zapSettings.zapToken,
            "Swap pair supplied does not have the reward token as one of it's pair"
        );
        zapSettings = _zapSettings;
        IERC20(zapSettings.zapToken).approve(zapSettings.zapContract, type(uint256).max);
    }

    function _depositMasterchef(uint256 _pid, uint256 _amount) internal override {
        abracadabraChef.deposit(_pid, _amount);
    }

    function _withdrawMasterchef(uint256 _pid, uint256 _amount) internal override {
        abracadabraChef.withdraw(_pid, _amount);
    }

    function _emergencyWithdraw(uint256 _pid) internal override {
        abracadabraChef.emergencyWithdraw(_pid);
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
        uint256 pendingIce = abracadabraChef.pendingIce(_pid, _user);
        return (pendingIce, 0, address(0));
    }

    function _getRewards(uint256 _pid) internal override {
        abracadabraChef.withdraw(_pid, 0);
    }

    function _getDepositBalance(uint256 pid, address user) internal view override returns (uint256 amount) {
        (amount, , ) = abracadabraChef.userInfo(pid, user);
    }

    function setMaxSlippageBips(uint256 _maxSlippageBips) external onlyDev {
        zapSettings.maxSlippage = _maxSlippageBips;
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

    function _bip() internal pure override returns (uint256) {
        return 10000;
    }

    function _convertRewardTokenToDepositToken(uint256 fromAmount) internal override returns (uint256 toAmount) {
        return CurveSwap.zapToStableLP(fromAmount, address(rewardToken), address(depositToken), zapSettings);
    }
}
