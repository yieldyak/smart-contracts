// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IWombatPool {
    function addressOfAsset(address token) external view returns (address);

    function masterWombat() external view returns (address);

    function deposit(
        address token,
        uint256 amount,
        uint256 minimumLiquidity,
        address to,
        uint256 deadline,
        bool shouldStake
    ) external returns (uint256 liquidity);

    function withdraw(address token, uint256 liquidity, uint256 minimumAmount, address to, uint256 deadline)
        external
        returns (uint256 amount);

    function quotePotentialWithdraw(address token, uint256 liquidity)
        external
        view
        returns (uint256 amount, uint256 fee);
}
