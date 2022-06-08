// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../LendingStrategy.sol";
import "../../lib/SafeMath.sol";
import "./interfaces/IAaveV3IncentivesController.sol";
import "./interfaces/ILendingPoolAaveV3.sol";

contract AaveV3Strategy is LendingStrategy {
    using SafeMath for uint256;

    struct LeverageSettings {
        uint256 leverageLevel;
        uint256 safetyFactor;
        uint256 leverageBips;
        uint256 minMinting;
    }

    uint256 public safetyFactor;
    uint256 public minMinting;

    address private avToken;
    address private avDebtToken;
    IAaveV3IncentivesController private rewardController;
    ILendingPoolAaveV3 private tokenDelegator;

    constructor(
        address _rewardController,
        address _tokenDelegator,
        address _avToken,
        address _avDebtToken,
        LeverageSettings memory _leverageSettings,
        address _swapPairDepositToken,
        RewardSwapPairs[] memory _rewardSwapPairs,
        BaseSettings memory _baseSettings,
        StrategySettings memory _strategySettings
    )
        LendingStrategy(
            _leverageSettings.leverageLevel,
            _leverageSettings.leverageBips,
            _swapPairDepositToken,
            _rewardSwapPairs,
            _baseSettings,
            _strategySettings
        )
    {
        rewardController = IAaveV3IncentivesController(_rewardController);
        tokenDelegator = ILendingPoolAaveV3(_tokenDelegator);
        _updateLeverage(
            _leverageSettings.leverageLevel,
            _leverageSettings.safetyFactor,
            _leverageSettings.minMinting,
            _leverageSettings.leverageBips
        );
        avToken = _avToken;
        avDebtToken = _avDebtToken;
    }

    function updateLeverage(
        uint256 _leverageLevel,
        uint256 _safetyFactor,
        uint256 _minMinting,
        uint256 _leverageBips
    ) external onlyDev {
        _updateLeverage(_leverageLevel, _safetyFactor, _minMinting, _leverageBips);
        (uint256 balance, uint256 borrowed, ) = _getAccountData();
        _unrollDebt(balance - borrowed);
        _rollupDebt();
    }

    function _updateLeverage(
        uint256 _leverageLevel,
        uint256 _safetyFactor,
        uint256 _minMinting,
        uint256 _leverageBips
    ) internal {
        leverageLevel = _leverageLevel;
        leverageBips = _leverageBips;
        safetyFactor = _safetyFactor;
        minMinting = _minMinting;
    }

    function getActualLeverage() public view returns (uint256) {
        (uint256 balance, uint256 borrowed, ) = _getAccountData();
        return balance.mul(1e18).div(balance.sub(borrowed));
    }

    function _supplyAssets(uint256 _amount) internal override {
        IERC20(asset).approve(address(tokenDelegator), _amount);
        tokenDelegator.supply(asset, _amount, address(this), 0);
    }

    function _withdrawAssets(uint256 _amount) internal override returns (uint256 _withdrawAmount) {
        (uint256 balance, , ) = _getAccountData();
        _amount = _amount > balance ? type(uint256).max : _amount;
        _withdrawAmount = tokenDelegator.withdraw(asset, _amount, address(this));
    }

    function _rollupDebt() internal override {
        (uint256 balance, uint256 borrowed, uint256 borrowable) = _getAccountData();
        uint256 lendTarget = balance.sub(borrowed).mul(leverageLevel.sub(safetyFactor)).div(leverageBips);
        IERC20(asset).approve(address(tokenDelegator), lendTarget);
        while (balance < lendTarget) {
            if (balance.add(borrowable) > lendTarget) {
                borrowable = lendTarget.sub(balance);
            }

            if (borrowable < minMinting) {
                break;
            }

            tokenDelegator.borrow(
                asset,
                borrowable,
                2, // variable interest model
                0,
                address(this)
            );

            tokenDelegator.supply(asset, borrowable, address(this), 0);
            (balance, borrowed, borrowable) = _getAccountData();
        }
        IERC20(asset).approve(address(tokenDelegator), 0);
    }

    function _unrollDebt(uint256 _amountToFreeUp) internal override {
        (uint256 balance, uint256 borrowed, ) = _getAccountData();
        uint256 targetBorrow = balance
            .sub(borrowed)
            .sub(_amountToFreeUp)
            .mul(leverageLevel.sub(safetyFactor))
            .div(leverageBips)
            .sub(balance.sub(borrowed).sub(_amountToFreeUp));
        uint256 toRepay = borrowed.sub(targetBorrow);
        if (toRepay > 0) {
            tokenDelegator.repayWithATokens(asset, toRepay, 2);
        }
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        address[] memory assets = new address[](2);
        assets[0] = avToken;
        assets[1] = avDebtToken;
        (address[] memory rewards, uint256[] memory amounts) = rewardController.getAllUserRewards(
            assets,
            address(this)
        );

        Reward[] memory pendingRewards = new Reward[](rewards.length);
        for (uint256 i = 0; i < rewards.length; i++) {
            pendingRewards[i] = Reward({reward: rewards[i], amount: amounts[i]});
        }
        return pendingRewards;
    }

    function _getRewards() internal override {
        address[] memory assets = new address[](2);
        assets[0] = avToken;
        assets[1] = avDebtToken;
        rewardController.claimAllRewards(assets, address(this));
    }

    function _emergencyWithdraw() internal override {
        (uint256 balance, uint256 borrowed, ) = _getAccountData();
        _unrollDebt(balance.sub(borrowed));
        tokenDelegator.withdraw(asset, type(uint256).max, address(this));
    }

    /// @notice Internal method to get account state
    /// @dev Values provided in 1e18 (WAD) instead of 1e27 (RAY)
    function _getAccountData()
        internal
        view
        returns (
            uint256 balance,
            uint256 borrowed,
            uint256 borrowable
        )
    {
        balance = IERC20(avToken).balanceOf(address(this));
        borrowed = IERC20(avDebtToken).balanceOf(address(this));
        borrowable = 0;
        if (balance.mul(leverageLevel.sub(leverageBips)).div(leverageLevel) > borrowed) {
            borrowable = balance.mul(leverageLevel.sub(leverageBips)).div(leverageLevel).sub(borrowed);
        }
    }

    function totalAssets() public view override returns (uint256) {
        (uint256 balance, uint256 borrowed, ) = _getAccountData();
        return balance.sub(borrowed);
    }
}
