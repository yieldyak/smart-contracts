// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

interface IVectorPoolHelperV2 {
    function depositTokenBalance(address _account) external view returns (uint256);

    function mainStaking() external view returns (address);

    function masterVtx() external view returns (address);

    function stakingToken() external view returns (address);

    function earned(address token) external view returns (uint256 vtxAmount, uint256 tokenAmount);

    function deposit(uint256 _amount) external;

    function stake(uint256 _amount) external;

    function withdraw(uint256 amount, uint256 minAmount) external;

    function getReward() external;
}
