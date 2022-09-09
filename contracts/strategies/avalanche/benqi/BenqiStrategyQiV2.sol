// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../VariableRewardsStrategyForSA.sol";
import "./lib/BenqiLibrary.sol";
import "./interfaces/IBenqiUnitroller.sol";
import "./interfaces/IBenqiERC20Delegator.sol";

contract BenqiStrategyQiV2 is VariableRewardsStrategyForSA {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address private constant QI = 0x8729438EB15e2C8B576fCc6AeCdA6A148776C0F5;

    IBenqiUnitroller private rewardController;
    IBenqiERC20Delegator private tokenDelegator;

    uint256 private leverageLevel;
    uint256 private leverageBips;
    uint256 private minMinting;
    uint256 private redeemLimitSafetyMargin;

    constructor(
        address _swapPairDepositToken,
        address _rewardController,
        address _tokenDelegator,
        VariableRewardsStrategySettings memory _settings,
        StrategySettings memory _strategySettings
    ) VariableRewardsStrategyForSA(_swapPairDepositToken, _settings, _strategySettings) {
        rewardController = IBenqiUnitroller(_rewardController);
        tokenDelegator = IBenqiERC20Delegator(_tokenDelegator);
        _enterMarket();
    }

    function _depositToStakingContract(uint256 _amount) internal override {
        depositToken.approve(address(tokenDelegator), _amount);
        require(tokenDelegator.mint(_amount) == 0, "Deposit failed");
        depositToken.approve(address(tokenDelegator), 0);
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 _withdrawAmount) {
        require(tokenDelegator.redeemUnderlying(_amount) == 0, "failed to redeem");
        return _amount;
    }

    function _emergencyWithdraw() internal override {
        tokenDelegator.redeemUnderlying(tokenDelegator.balanceOfUnderlying(address(this)));
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        Reward[] memory pendingRewards = new Reward[](rewardCount);
        for (uint256 i = 0; i < rewardCount; i++) {
            pendingRewards[i] = Reward({
                reward: supportedRewards[i],
                amount: _calculateReward(uint8(i), address(this))
            });
        }
        return pendingRewards;
    }

    function _getRewards() internal override {
        address[] memory markets = new address[](1);
        markets[0] = address(tokenDelegator);
        for (uint256 i = 0; i < rewardCount; i++) {
            rewardController.claimReward(0, address(this), markets);
        }
    }

    function totalDeposits() public view override returns (uint256) {
        (, uint256 internalBalance, , uint256 exchangeRate) = tokenDelegator.getAccountSnapshot(address(this));
        return internalBalance.mul(exchangeRate).div(1e18);
    }

    function _enterMarket() internal {
        address[] memory tokens = new address[](1);
        tokens[0] = address(tokenDelegator);
        rewardController.enterMarkets(tokens);
    }

    function _calculateReward(uint8 tokenIndex, address account) internal view returns (uint256) {
        uint256 rewardAccrued = rewardController.rewardAccrued(tokenIndex, account);
        uint256 supplyAccrued = BenqiLibrary.supplyAccrued(rewardController, tokenDelegator, tokenIndex, account);
        return rewardAccrued.add(supplyAccrued);
    }
}
