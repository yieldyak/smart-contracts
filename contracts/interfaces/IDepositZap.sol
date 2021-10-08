// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface IDepositZap {
    function add_liquidity(uint[] _underlying_amounts,uint _min_mint_amount) external returns (uint256);
    function calc_token_amount(uint256[]_amounts,bool _is_deposit) external view returns (uint256);
    function underlying_coins(uint index_of_coin) external view returns (address);
}