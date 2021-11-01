// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface IElevenGrowthVault {
    function strategy() external view returns (address);

    function token() external view returns (address);

    function balance() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function available() external view returns (uint256);

    function getPricePerFullShare() external view returns (uint256);

    function depositAll() external;

    function deposit(uint256 _amount) external;

    function earn() external;

    function withdrawAll() external;

    function withdraw(uint256 _shares) external;
}
