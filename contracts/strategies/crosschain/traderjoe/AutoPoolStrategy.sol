// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../BaseStrategy.sol";

import "./interfaces/IAPTFarm.sol";
import "./interfaces/IAutomatedPoolToken.sol";

contract AutoPoolStrategy is BaseStrategy {
    IAPTFarm public stakingContract;
    uint256 public immutable PID;
    address public immutable pairTokenIn;

    address private immutable JOE;
    address private immutable tokenX;
    address private immutable tokenY;

    constructor(
        address _stakingContract,
        address _pairTokenIn,
        BaseStrategySettings memory _settings,
        StrategySettings memory _strategySettings
    ) BaseStrategy(_settings, _strategySettings) {
        stakingContract = IAPTFarm(_stakingContract);
        PID = stakingContract.vaultFarmId(address(depositToken));
        JOE = stakingContract.joe();
        tokenX = IAutomatedPoolToken(address(depositToken)).getTokenX();
        tokenY = IAutomatedPoolToken(address(depositToken)).getTokenY();
        require(_pairTokenIn == tokenX || _pairTokenIn == tokenY, "AutoPoolStrategy::Invalid configuration");
        pairTokenIn = _pairTokenIn;
    }

    function _depositToStakingContract(uint256 _amount, uint256) internal override {
        depositToken.approve(address(stakingContract), _amount);
        stakingContract.deposit(PID, _amount);
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 withdrawAmount) {
        stakingContract.withdraw(PID, _amount);
        return _amount;
    }

    function _emergencyWithdraw() internal override {
        stakingContract.withdraw(PID, totalDeposits());
        depositToken.approve(address(stakingContract), 0);
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        (uint256 pendingJoe, address bonusTokenAddress,, uint256 pendingBonusToken) =
            stakingContract.pendingTokens(PID, address(this));
        Reward[] memory pendingRewards = new Reward[](supportedRewards.length);
        for (uint256 i = 0; i < pendingRewards.length; i++) {
            address supportedReward = supportedRewards[i];
            uint256 amount;
            if (supportedReward == JOE) {
                amount = pendingJoe;
            } else if (supportedReward == bonusTokenAddress) {
                amount = pendingBonusToken;
            }
            pendingRewards[i] = Reward({reward: supportedReward, amount: amount});
        }
        return pendingRewards;
    }

    function _getRewards() internal override {
        uint256[] memory pids = new uint[](1);
        pids[0] = PID;
        stakingContract.harvestRewards(pids);
    }

    function _convertRewardTokenToDepositToken(uint256 _fromAmount) internal override returns (uint256 toAmount) {
        if (pairTokenIn != address(rewardToken)) {
            FormattedOffer memory offer = simpleRouter.query(_fromAmount, address(rewardToken), pairTokenIn);
            _fromAmount = _swap(offer);
        }
        uint256 amountX;
        uint256 amountY;
        if (pairTokenIn == tokenX) {
            amountX = _fromAmount;
        } else {
            amountY = _fromAmount;
        }
        IERC20(pairTokenIn).approve(address(depositToken), _fromAmount);
        (toAmount,,) = IAutomatedPoolToken(address(depositToken)).deposit(amountX, amountY);
    }

    function totalDeposits() public view override returns (uint256) {
        IAPTFarm.UserInfo memory userInfo = stakingContract.userInfo(PID, address(this));
        return userInfo.amount;
    }
}
