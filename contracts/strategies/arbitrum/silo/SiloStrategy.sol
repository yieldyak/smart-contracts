// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../../BaseStrategy.sol";
import "./interfaces/ISilo.sol";
import "./interfaces/ISiloRepository.sol";
import "./interfaces/IIncentivesController.sol";
import "./interfaces/ISiloLens.sol";

contract SiloStrategy is BaseStrategy {
    ISilo immutable silo;
    ISiloRepository immutable siloRepository;
    ISiloLens immutable siloLens;

    IIncentivesController incentivesController;
    address[] siloTokens;

    constructor(
        address _siloRepository,
        address _siloIncentivesController,
        address _siloLens,
        address _silo,
        BaseStrategySettings memory _baseStrategySettings,
        StrategySettings memory _strategySettings
    ) BaseStrategy(_baseStrategySettings, _strategySettings) {
        siloRepository = ISiloRepository(_siloRepository);
        silo = _silo > address(0) ? ISilo(_silo) : ISilo(siloRepository.getSilo(address(depositToken)));
        incentivesController = IIncentivesController(_siloIncentivesController);
        siloLens = ISiloLens(_siloLens);
        (address[] memory assets, ISilo.AssetStorage[] memory assetsStorage) = silo.getAssetsWithState();
        for (uint256 i; i < assetsStorage.length; i++) {
            if (assets[i] == address(depositToken)) {
                siloTokens.push(assetsStorage[i].collateralToken);
            }
        }
    }

    function updateIncentivesController(address _siloIncentivesController) public onlyDev {
        incentivesController = IIncentivesController(_siloIncentivesController);
    }

    function _depositToStakingContract(uint256 _amount, uint256) internal override {
        depositToken.approve(address(silo), _amount);
        silo.deposit(address(depositToken), _amount, false);
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 _withdrawAmount) {
        (_withdrawAmount,) = silo.withdraw(address(depositToken), _amount, false);
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        Reward[] memory pendingRewards = new Reward[](supportedRewards.length);
        for (uint256 i; i < pendingRewards.length; i++) {
            address reward = supportedRewards[i];
            uint256 pending = incentivesController.getRewardsBalance(siloTokens, address(this));
            pendingRewards[i] = Reward({reward: reward, amount: pending});
        }
        return pendingRewards;
    }

    function _getRewards() internal override {
        incentivesController.claimRewardsToSelf(siloTokens, type(uint256).max);
    }

    function totalDeposits() public view override returns (uint256) {
        return siloLens.getDepositAmount(address(silo), address(depositToken), address(this), block.timestamp);
    }

    function _emergencyWithdraw() internal override {
        silo.withdraw(address(depositToken), totalDeposits(), false);
        depositToken.approve(address(silo), 0);
    }
}
