// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IPoolDepositor {
    function deposit(address _lptoken, uint256 _amount, uint256 _minLiquidity, bool _stake) external;
    function withdraw(address _lptoken, uint256 _amount, uint256 _minOut, address _recipient) external;
    function getWithdrawAmountOut(address _lptoken, uint256 _amount)
        external
        view
        returns (uint256 amount, uint256 fee);
    function getDepositAmountOut(address _lptoken, uint256 _amount)
        external
        view
        returns (uint256 liquidity, uint256 reward);
    function booster() external view returns (address);
    function lpTokenToPid(address wombatAsset) external view returns (uint256);
}
