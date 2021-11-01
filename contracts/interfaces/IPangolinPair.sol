// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "./IPangolinERC20.sol";

interface IPangolinPair is IPangolinERC20 {
    function token0() external pure returns (address);

    function token1() external pure returns (address);
}
