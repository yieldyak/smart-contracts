// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IWooStakingVault {
    function instantWithdraw(uint256 shares) external;

    function balanceOf(address user) external view returns (uint256);

    function withdrawFee() external view returns (uint256);
}
