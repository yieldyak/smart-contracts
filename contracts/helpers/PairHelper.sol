// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "../interfaces/IZEROPair.sol";
import "../interfaces/IERC20.sol";

contract PairHelper {
    struct PairInfo {
        string symbol;
        uint256 totalSupply;
        address token0;
        address token1;
        string token0Symbol;
        string token1Symbol;
        uint256 reserve0;
        uint256 reserve1;
    }

    constructor() {}

    function pairInfo(address pairAddress) public view returns (PairInfo memory) {
        IZEROPair pair = IZEROPair(pairAddress);
        PairInfo memory info;
        info.symbol = pair.symbol();
        info.totalSupply = pair.totalSupply();
        info.token0 = pair.token0();
        info.token1 = pair.token1();

        info.token0Symbol = IERC20(info.token0).symbol();
        info.token1Symbol = IERC20(info.token1).symbol();

        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
        info.reserve0 = reserve0;
        info.reserve1 = reserve1;
        return info;
    }
}
