// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

interface IVectorMainStaking {
    function getSharesForDepositTokens(uint256 amount, address token) external view returns (uint256);

    function getDepositTokensForShares(uint256 amount, address token) external view returns (uint256);
}
