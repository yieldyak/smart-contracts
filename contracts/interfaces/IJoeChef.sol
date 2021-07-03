// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "./IChef.sol";

interface IJoeChef is IChef {
    function pendingTokens(uint256 _pid, address _user) external view returns (uint256 pendingJoe, address bonusTokenAddress, string memory bonusTokenSymbol, uint256 pendingBonusToken);
    function userInfo(uint pid, address user) external view returns (
        uint256 amount,
        uint256 rewardDebt
    );
}