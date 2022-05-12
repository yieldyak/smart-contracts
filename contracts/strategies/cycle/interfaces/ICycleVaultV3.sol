// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface ICycleVaultV3 {
    // Balance helpers
    function balanceLPinVault() external view returns (uint256);

    function balanceLPinSystem() external view returns (uint256);

    function accountShareBalance(address account) external view returns (uint256);

    function getAccountLP(address account) external view returns (uint256);

    function getLPamountForShares(uint256 shares) external view returns (uint256);

    // Account access functions
    function depositLP(uint256 amount) external;

    function withdrawLP(uint256 sharesToWithdraw) external;
}
