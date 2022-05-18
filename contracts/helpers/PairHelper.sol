// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;
pragma experimental ABIEncoderV2;

interface IPair {
    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

    function totalSupply() external view returns (uint256);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );
}

contract PairHelper {
    struct PairInfo {
        string symbol;
        uint256 totalSupply;
        address token0;
        address token1;
        string token0Symbol;
        string token1Symbol;
        uint8 token0Decimals;
        uint8 token1Decimals;
        uint256 reserve0;
        uint256 reserve1;
    }

    constructor() {}

    function pairInfo(address pairAddress) public view returns (PairInfo memory) {
        IPair pair = IPair(pairAddress);
        PairInfo memory info;
        info.symbol = pair.symbol();
        info.totalSupply = pair.totalSupply();
        info.token0 = pair.token0();
        info.token1 = pair.token1();

        info.token0Symbol = IPair(info.token0).symbol();
        info.token1Symbol = IPair(info.token1).symbol();

        info.token0Decimals = IPair(info.token0).decimals();
        info.token1Decimals = IPair(info.token1).decimals();

        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
        info.reserve0 = reserve0;
        info.reserve1 = reserve1;
        return info;
    }
}
