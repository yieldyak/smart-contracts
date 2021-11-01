// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}

contract BalancesOfHelper {
    constructor() {}

    /**
     * @notice Fetch many token balances for a single account
     * @param account account
     * @param tokenAddresses list of token addresses
     */
    function accountBalancesOf(address account, address[] memory tokenAddresses)
        public
        view
        returns (uint256[] memory)
    {
        uint256[] memory balances = new uint256[](tokenAddresses.length);
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            uint256 balance = IERC20(tokenAddresses[i]).balanceOf(account);
            balances[i] = balance;
        }
        return balances;
    }

    /**
     * @notice Fetch many token balances for a many accounts
     * @param accounts list of accounts
     * @param tokenAddresses list of token addresses
     */
    function accountsBalancesOf(address[] memory accounts, address[] memory tokenAddresses)
        public
        view
        returns (uint256[] memory)
    {
        require(accounts.length == tokenAddresses.length, "not same length");
        uint256[] memory balances = new uint256[](tokenAddresses.length);
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            uint256 balance = IERC20(tokenAddresses[i]).balanceOf(accounts[i]);
            balances[i] = balance;
        }
        return balances;
    }

    /**
     * @notice Fetch a token balance for many accounts
     * @param accounts list of accounts
     * @param tokenAddress token addresses
     */
    function accountsBalanceOf(address[] memory accounts, address tokenAddress) public view returns (uint256[] memory) {
        uint256[] memory balances = new uint256[](accounts.length);
        for (uint256 i = 0; i < accounts.length; i++) {
            uint256 balance = IERC20(tokenAddress).balanceOf(accounts[i]);
            balances[i] = balance;
        }
        return balances;
    }
}
