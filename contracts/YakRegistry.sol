// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "./lib/Ownable.sol";
import "./lib/EnumerableSet.sol";
import "./YakStrategy.sol";

/**
 * @notice YakRegistry is a list of officially supported strategies.
 * @dev DRAFT
 */
contract YakRegistry is Ownable {
    uint256 public strategiesLength;
    mapping(address => uint256[]) public strategyIdsForDepositToken;

    mapping(address => bool) private registeredStrategies;
    address[] private strategies;

    struct StrategyInfo {
        uint256 id;
        address strategyAddress;
        bool depositsEnabled;
        address depositToken;
        address rewardToken;
        uint256 minTokensToReinvest;
        uint256 maxTokensToDepositWithoutReinvest;
        uint256 adminFeeBips;
        uint256 devFeeBips;
        uint256 reinvestRewardBips;
    }

    event AddStrategy(address indexed strategy);
    event RemoveStrategy(address indexed strategy);

    constructor() {}

    function isActiveStrategy(address _strategy) external view returns (bool) {
        YakStrategy strategy = YakStrategy(_strategy);
        return registeredStrategies[_strategy] && strategy.DEPOSITS_ENABLED();
    }

    function strategiesForDepositTokenCount(address depositToken) external view returns (uint256) {
        return strategyIdsForDepositToken[depositToken].length;
    }

    function strategyInfo(uint256 id) external view returns (StrategyInfo memory) {
        YakStrategy strategy = YakStrategy(strategies[id]);
        return
            StrategyInfo({
                id: id,
                strategyAddress: address(strategy),
                depositsEnabled: strategy.DEPOSITS_ENABLED(),
                depositToken: address(strategy.depositToken()),
                rewardToken: address(strategy.rewardToken()),
                minTokensToReinvest: strategy.MIN_TOKENS_TO_REINVEST(),
                maxTokensToDepositWithoutReinvest: strategy.MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST(),
                adminFeeBips: strategy.ADMIN_FEE_BIPS(),
                devFeeBips: strategy.DEV_FEE_BIPS(),
                reinvestRewardBips: strategy.REINVEST_REWARD_BIPS()
            });
    }

    function addStrategy(address strategyAddress) external onlyOwner {
        strategies.push(strategyAddress);
        strategiesLength++;
        uint256 id = strategies.length - 1;
        address depositToken = address(YakStrategy(strategyAddress).depositToken());
        strategyIdsForDepositToken[depositToken].push(id);
        _addRegisteredStrategy(strategyAddress);
    }

    function _addRegisteredStrategy(address strategy) private {
        registeredStrategies[strategy] = true;
        emit AddStrategy(strategy);
    }
}
