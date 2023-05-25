// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface ITokenMinter {
    function getFactAmounMint(uint256 _amount) external view returns (uint256 amount);
}
