// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface ICurveCryptoSwap {
    function calc_token_amount(uint256[5] memory _amounts, bool _is_deposit) external view returns(uint);
    function add_liquidity(uint256[5] memory _amounts, uint256 _min_mint_amount, bool _use_underlying) external returns(uint);
}