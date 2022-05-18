// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../../interfaces/IERC20.sol";

interface IKyberPair is IERC20 {
    function token0() external pure returns (address);

    function token1() external pure returns (address);

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;

    function getReserves() external view returns (uint112 reserve0, uint112 reserve1);

    function getTradeInfo()
        external
        view
        returns (
            uint112 _reserve0,
            uint112 _reserve1,
            uint112 _vReserve0,
            uint112 _vReserve1,
            uint256 feeInPrecision
        );

    function mint(address to) external returns (uint256 liquidity);

    function sync() external;
}
