// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

interface IPlatypusVoterProxy {
    function withdraw(
        uint256 _pid,
        address _stakingContract,
        address _pool,
        address _token,
        address _asset,
        uint256 _maxSlippage,
        uint256 _amount
    ) external returns (uint256);

    function emergencyWithdraw(
        uint256 _pid,
        address _stakingContract,
        address _pool,
        address _token,
        address _asset
    ) external;

    function balanceOf(address _stakingContract, address _pool) external view returns (uint256);

    function deposit(
        uint256 _pid,
        address _stakingContract,
        address _pool,
        address _token,
        address _asset,
        uint256 _amount
    ) external;

    function platypusVoter() external view returns (address);

    function claimReward(
        address _stakingContract,
        uint256 _pid,
        address _asset
    ) external;

    function approveStrategy(address _asset, address _strategy) external;
}
