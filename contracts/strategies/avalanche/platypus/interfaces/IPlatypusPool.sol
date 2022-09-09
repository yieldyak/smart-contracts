// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IPlatypusPool {
    function assetOf(address token) external view returns (address);

    function deposit(
        address to,
        uint256 amount,
        address token,
        uint256 deadline
    ) external returns (uint256);

    function withdraw(
        address token,
        uint256 liquidity,
        uint256 minimumAmount,
        address to,
        uint256 deadline
    ) external returns (uint256);

    function getHaircutRate() external view returns (uint256);

    function quotePotentialWithdraw(address token, uint256 liquidity)
        external
        view
        returns (
            uint256,
            uint256,
            bool
        );

    function getC1() external view returns (uint256);

    function getXThreshold() external view returns (uint256);

    function getSlippageParamK() external view returns (uint256);

    function getSlippageParamN() external view returns (uint256);

    function quotePotentialSwap(
        address fromToken,
        address toToken,
        uint256 fromAmount
    ) external view returns (uint256, uint256);

    function swap(
        address fromToken,
        address toToken,
        uint256 fromAmount,
        uint256 minimumToAmount,
        address to,
        uint256 deadline
    ) external returns (uint256 actualToAmount, uint256 haircut);
}
