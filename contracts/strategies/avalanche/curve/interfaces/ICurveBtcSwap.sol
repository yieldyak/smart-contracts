// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface ICurveBtcSwap {
    function calc_token_amount(uint256[2] memory _amounts, bool _is_deposit) external view returns (uint256);

    function add_liquidity(
        uint256[2] memory _amounts,
        uint256 _min_mint_amount,
        bool _use_underlying
    ) external;

    function underlying_coins(uint256 index) external view returns (address);
}
