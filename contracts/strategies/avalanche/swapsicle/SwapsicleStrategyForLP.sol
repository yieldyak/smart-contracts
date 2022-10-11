// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../VariableRewardsStrategyForLP.sol";
import "../../../interfaces/IERC20.sol";

import "./interfaces/ISwapsicleChef.sol";

contract SwapsicleStrategyForLP is VariableRewardsStrategyForLP {
    address private constant POPS = 0x240248628B7B6850352764C5dFa50D1592A033A8;

    ISwapsicleChef public swapsicleChef;
    uint256 public immutable PID;

    constructor(
        address _stakingContract,
        uint256 _pid,
        SwapPairs memory _swapPairs,
        VariableRewardsStrategySettings memory _settings,
        StrategySettings memory _strategySettings
    ) VariableRewardsStrategyForLP(_swapPairs, _settings, _strategySettings) {
        swapsicleChef = ISwapsicleChef(_stakingContract);
        PID = _pid;
    }

    function _depositToStakingContract(uint256 _amount, uint256) internal override {
        IERC20(depositToken).approve(address(swapsicleChef), _amount);
        swapsicleChef.deposit(PID, _amount);
        IERC20(depositToken).approve(address(swapsicleChef), 0);
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 _withdrawAmount) {
        swapsicleChef.withdraw(PID, _amount);
        return _amount;
    }

    function _emergencyWithdraw() internal override {
        IERC20(depositToken).approve(address(swapsicleChef), 0);
        swapsicleChef.emergencyWithdraw(PID);
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        uint256 pendingPops = swapsicleChef.pendingPops(PID, address(this));
        Reward[] memory pendingRewards = new Reward[](1);

        pendingRewards[0] = Reward({reward: POPS, amount: pendingPops});
        return pendingRewards;
    }

    function _getRewards() internal override {
        swapsicleChef.deposit(PID, 0);
    }

    function totalDeposits() public view override returns (uint256) {
        (uint256 amount, ) = swapsicleChef.userInfo(PID, address(this));
        return amount;
    }
}
