// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

interface ICurveFactory4AssetsZap {
    function calc_token_amount(
        address _pool,
        uint256[4] memory _amounts,
        bool _is_deposit
    ) external view returns (uint256);

    function add_liquidity(
        address _pool,
        uint256[4] memory _amounts,
        uint256 _min_mint_amount
    ) external;
}
