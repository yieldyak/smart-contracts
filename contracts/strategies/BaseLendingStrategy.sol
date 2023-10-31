// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./BaseStrategy.sol";

abstract contract BaseLendingStrategy is BaseStrategy {
    struct BaseLendingStrategySettings {
        uint256 leverageLevel;
        uint256 leverageBips;
    }

    uint256 public leverageLevel;
    uint256 public leverageBips;

    constructor(
        BaseLendingStrategySettings memory _baseLendingStrategySettings,
        BaseStrategySettings memory _baseStrategySettings,
        StrategySettings memory _strategySettings
    ) BaseStrategy(_baseStrategySettings, _strategySettings) {
        leverageLevel = _baseLendingStrategySettings.leverageLevel;
        leverageBips = _baseLendingStrategySettings.leverageBips;
    }

    /*//////////////////////////////////////////////////////////////
                            ABSTRACT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _supplyAssets(uint256 _amount) internal virtual;

    function _withdrawAssets(uint256 _amount) internal virtual returns (uint256 withdrawAmount);

    function _rollupDebt() internal virtual;

    function _unrollDebt(uint256 _amountNeeded) internal virtual;

    /*//////////////////////////////////////////////////////////////
                                DEPOSIT
    //////////////////////////////////////////////////////////////*/

    function _depositToStakingContract(uint256 _amount, uint256) internal override {
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
