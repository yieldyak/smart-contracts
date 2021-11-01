// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "./lib/Ownable.sol";

/**
 * @notice YakRegistry is a list of officially supported strategies.
 * @dev DRAFT
 */
contract YakRegistry is Ownable {
    mapping(address => bool) public registeredStrategies;

    event AddStrategy(address indexed strategy);
    event RemoveStrategy(address indexed strategy);

    constructor() {}

    function addStrategies(address[] calldata strategies) external onlyOwner {
        for (uint256 i = 0; i < strategies.length; i++) {
            _addStrategy(strategies[i]);
        }
    }

    function removeStrategies(address[] calldata strategies) external onlyOwner {
        for (uint256 i = 0; i < strategies.length; i++) {
            _removeStrategy(strategies[i]);
        }
    }

    function _addStrategy(address strategy) private {
        registeredStrategies[strategy] = true;
        emit AddStrategy(strategy);
    }

    function _removeStrategy(address strategy) private {
        registeredStrategies[strategy] = false;
        emit RemoveStrategy(strategy);
    }
}
