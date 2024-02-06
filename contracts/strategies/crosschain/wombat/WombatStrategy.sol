// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../BaseStrategy.sol";
import "./interfaces/IBoostedMasterWombat.sol";
import "./interfaces/IWombatAsset.sol";
import "./interfaces/IWombatPool.sol";

contract WombatStrategy is BaseStrategy {
    using SafeERC20 for IERC20;

    IBoostedMasterWombat public immutable masterWombat;
    IWombatAsset public immutable wombatAsset;
    IWombatPool public immutable wombatPool;
    uint256 public immutable pid;

    constructor(
        address _wombatPool,
        BaseStrategySettings memory baseStrategySettings,
        StrategySettings memory _strategySettings
    ) BaseStrategy(baseStrategySettings, _strategySettings) {
        wombatPool = IWombatPool(_wombatPool);
        wombatAsset = IWombatAsset(wombatPool.addressOfAsset(address(depositToken)));
        masterWombat = IBoostedMasterWombat(wombatPool.masterWombat());
        pid = masterWombat.getAssetPid(address(wombatAsset));
    }

    function _depositToStakingContract(uint256 _amount, uint256) internal override {
        depositToken.approve(address(wombatPool), _amount);
        wombatPool.deposit(address(depositToken), _amount, 0, address(this), block.timestamp, true);
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 _withdrawAmount) {
        (uint128 lpBalance,,,) = masterWombat.userInfo(pid, address(this));
        uint256 liquidity = (_amount * lpBalance) / totalDeposits();
        liquidity = liquidity > lpBalance ? lpBalance : liquidity;
        masterWombat.withdraw(pid, liquidity);
        IERC20(address(wombatAsset)).approve(address(wombatPool), liquidity);
        _withdrawAmount = wombatPool.withdraw(address(depositToken), liquidity, 0, address(this), block.timestamp);
    }

    function _emergencyWithdraw() internal override {
        depositToken.approve(address(masterWombat), 0);
        masterWombat.emergencyWithdraw(pid);
        uint256 assetBalance = IERC20(address(wombatAsset)).balanceOf(address(this));
        IERC20(address(wombatAsset)).approve(address(wombatPool), assetBalance);
        wombatPool.withdraw(address(depositToken), assetBalance, 0, address(this), block.timestamp);
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        (, address[] memory bonusTokenAddresses,, uint256[] memory pendingBonusRewards) =
            masterWombat.pendingTokens(pid, address(this));
        Reward[] memory pendingRewards = new Reward[](bonusTokenAddresses.length);
        for (uint256 i = 0; i < bonusTokenAddresses.length; i++) {
            pendingRewards[i] = Reward({reward: bonusTokenAddresses[i], amount: pendingBonusRewards[i]});
        }
        return pendingRewards;
    }

    function _getRewards() internal override {
        masterWombat.deposit(pid, 0);
    }

    function totalDeposits() public view override returns (uint256) {
        (uint128 liquidity,,,) = masterWombat.userInfo(pid, address(this));
        if (liquidity == 0) return 0;
        (uint256 amount, uint256 fee) = wombatPool.quotePotentialWithdraw(address(depositToken), liquidity);
        return amount + fee;
    }
}
