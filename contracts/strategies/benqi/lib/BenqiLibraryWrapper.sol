// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./BenqiLibrary.sol";
import "../interfaces/IBenqiLibrary.sol";

import "../interfaces/IBenqiUnitroller.sol";
import "../interfaces/IBenqiERC20Delegator.sol";

contract BenqiLibraryWrapper is IBenqiLibrary {
    constructor() {}

    function calculateReward(
        address rewardController,
        address tokenDelegator,
        uint8 tokenIndex,
        address account
    ) external view returns (uint256) {
        return
            BenqiLibrary.calculateReward(
                IBenqiUnitroller(rewardController),
                IBenqiERC20Delegator(tokenDelegator),
                tokenIndex,
                account
            );
    }
}
