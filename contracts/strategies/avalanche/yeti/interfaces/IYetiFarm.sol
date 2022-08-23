// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IYetiFarm {
    function deposit(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function pendingTokens(address account) external view returns (uint256);

    function userInfo(address account)
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        );
}
