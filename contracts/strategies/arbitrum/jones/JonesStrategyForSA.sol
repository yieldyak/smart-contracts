// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../../BaseStrategy.sol";
import "./interfaces/IMiniChefV2.sol";

contract JonesStrategyForSA is BaseStrategy {
    uint256 private constant ACC_SUSHI_PRECISION = 1e12;

    IMiniChefV2 immutable miniChef;
    uint256 immutable PID;
    address immutable reward;

    struct JonesStrategySettings {
        uint256 pid;
        address miniChef;
    }

    constructor(
        JonesStrategySettings memory _jonesStrategySettings,
        BaseStrategySettings memory _baseStrategySettings,
        StrategySettings memory _strategySettings
    ) BaseStrategy(_baseStrategySettings, _strategySettings) {
        miniChef = IMiniChefV2(_jonesStrategySettings.miniChef);
        PID = _jonesStrategySettings.pid;
        reward = miniChef.SUSHI();
    }

    function _depositToStakingContract(uint256 _amount, uint256) internal override {
        depositToken.approve(address(miniChef), _amount);
        miniChef.deposit(PID, _amount, address(this));
    }

    function _getDepositFeeBips() internal view override returns (uint256) {
        (,,, uint256 depositFeeBips) = miniChef.poolInfo(PID);
        if (miniChef.incentivesOn() && depositFeeBips > 0 && miniChef.incentiveReceiver() > address(0)) {
            return depositFeeBips;
        }
        return 0;
    }

    function _bip() internal pure override returns (uint256) {
        return ACC_SUSHI_PRECISION;
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 _withdrawAmount) {
        miniChef.withdraw(PID, _amount, address(this));
        return _amount;
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        Reward[] memory pendingRewards = new Reward[](1);
        pendingRewards[0] = Reward({reward: reward, amount: miniChef.pendingSushi(PID, address(this))});
        return pendingRewards;
    }

    function _getRewards() internal override {
        miniChef.harvest(PID, address(this));
    }

    function totalDeposits() public view override returns (uint256 total) {
        (total,) = miniChef.userInfo(PID, address(this));
    }

    function _emergencyWithdraw() internal override {
        miniChef.emergencyWithdraw(PID, address(this));
        depositToken.approve(address(miniChef), 0);
    }
}
