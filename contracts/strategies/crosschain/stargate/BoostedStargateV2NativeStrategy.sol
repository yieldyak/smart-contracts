// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./../lamapay/LamaPayStrategyBase.sol";
import "./interfaces/IStargateStaking.sol";
import "./interfaces/IStargateMultiRewarder.sol";
import "./interfaces/IStargatePool.sol";
import "./lib/SafeCast.sol";

contract BoostedStargateV2NativeStrategy is LamaPayStrategyBase {
    IStargateStaking public immutable stargateStaking;
    IStargatePool public immutable stargatePool;
    uint8 immutable sharedDecimals;
    uint8 immutable tokenDecimals;

    constructor(
        address _stargateStaking,
        address _pool,
        BaseStrategySettings memory _baseStrategySettings,
        StrategySettings memory _strategySettings
    ) LamaPayStrategyBase(_baseStrategySettings, _strategySettings) {
        stargateStaking = IStargateStaking(_stargateStaking);
        stargatePool = IStargatePool(_pool);
        tokenDecimals = WGAS.decimals();
        sharedDecimals = stargatePool.sharedDecimals();
    }

    function _depositToStakingContract(uint256 _amount, uint256) internal override {
        depositToken.approve(address(stargateStaking), _amount);
        stargateStaking.deposit(address(depositToken), _amount);
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 _withdrawAmount) {
        stargateStaking.withdraw(address(depositToken), _amount);
        return _amount;
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        (address[] memory tokens, uint256[] memory amounts) = IStargateMultiRewarder(
            stargateStaking.rewarder(address(depositToken))
        ).getRewards(address(depositToken), address(this));

        uint256 length = tokens.length + streams.length;

        Reward[] memory rewards = new Reward[](length);
        uint256 i;
        for (i; i < streams.length; i++) {
            rewards[i] = _readStream(streams[i]);
        }
        for (uint256 j; j < tokens.length; j++) {
            rewards[i + j] = Reward({reward: tokens[j], amount: amounts[j]});
        }
        return rewards;
    }

    function _getRewards() internal override {
        super._getRewards();
        address[] memory tokens = new address[](1);
        tokens[0] = address(depositToken);
        stargateStaking.claim(tokens);
    }

    function _convertRewardTokenToDepositToken(uint256 _fromAmount) internal override returns (uint256 toAmount) {
        if (address(rewardToken) != address(WGAS)) {
            FormattedOffer memory offer = simpleRouter.query(_fromAmount, address(rewardToken), address(WGAS));
            _fromAmount = _swap(offer);
        }
        _fromAmount = removeRoundingErrors(_fromAmount);
        WGAS.withdraw(_fromAmount);
        return stargatePool.deposit{value: _fromAmount}(address(this), _fromAmount);
    }

    function removeRoundingErrors(uint256 _amount) internal view returns (uint256) {
        uint256 convertRate = 10 ** (tokenDecimals - sharedDecimals);
        unchecked {
            uint64 amountSD = SafeCast.toUint64(_amount / convertRate);
            return amountSD * convertRate;
        }
    }

    receive() external payable {
        require(msg.sender == address(WGAS));
    }

    function totalDeposits() public view override returns (uint256) {
        return stargateStaking.balanceOf(address(depositToken), address(this));
    }

    function _emergencyWithdraw() internal override {
        stargateStaking.emergencyWithdraw(address(depositToken));
        depositToken.approve(address(stargateStaking), 0);
    }
}
