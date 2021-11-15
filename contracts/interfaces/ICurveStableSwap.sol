// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface ICurveStableSwap {
    function calc_token_amount(uint256[3] memory _amounts, bool _is_deposit) external view returns (uint256);

    function add_liquidity(uint256[3] memory _amounts, uint256 _min_mint_amount) external returns (uint256);

    function underlying_coins(uint256 index) external view returns (address);
}
