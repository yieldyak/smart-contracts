// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./VariableRewardsStrategyForSA.sol";

abstract contract LendingStrategy is VariableRewardsStrategyForSA {
    uint256 public leverageLevel;
    uint256 public leverageBips;

    constructor(
        uint256 _leverageLevel,
        uint256 _leverageBips,
        address _swapPairDepositToken,
        RewardSwapPairs[] memory _rewardSwapPairs,
        BaseSettings memory _baseSettings,
        StrategySettings memory _strategySettings
    ) VariableRewardsStrategyForSA(_swapPairDepositToken, _rewardSwapPairs, _baseSettings, _strategySettings) {
        leverageLevel = _leverageLevel;
        leverageBips = _leverageBips;
    }

    /*//////////////////////////////////////////////////////////////
                            ABSTRACT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _supplyAssets(uint256 _amount) internal virtual;

    function _withdrawAssets(uint256 _amount) internal virtual returns (uint256 withdrawAmount);

    function _rollupDebt() internal virtual;

    function _unrollDebt(uint256 _amountToFreeUp) internal virtual;

    /*//////////////////////////////////////////////////////////////
                                DEPOSIT
    //////////////////////////////////////////////////////////////*/

    function _depositToStakingContract(uint256 _amount) internal override {
        _supplyAssets(_amount);
        _rollupDebt();
    }

    /*//////////////////////////////////////////////////////////////
                               WITHDRAW
    //////////////////////////////////////////////////////////////*/

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 withdrawAmount) {
        _unrollDebt(_amount);
        withdrawAmount = _withdrawAssets(_amount);
        _rollupDebt();
    }
}
