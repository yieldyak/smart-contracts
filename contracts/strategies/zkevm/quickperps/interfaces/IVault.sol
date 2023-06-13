// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IVault {
    function maxUsdqAmounts(address) external view returns (uint256);

    function usdqAmounts(address) external view returns (uint256);

    function usdq() external view returns (address);

    function getMinPrice(address _token) external view returns (uint256);

    function adjustForDecimals(uint256 _amount, address _tokenDiv, address _tokenMul) external view returns (uint256);
}
