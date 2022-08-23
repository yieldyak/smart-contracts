// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IYetiVoterProxy {
    function withdraw(
        address _stakingContract,
        address _token,
        uint256 _amount
    ) external;

    function emergencyWithdraw(address _stakingContract, address _token) external;

    function deposit(
        address _stakingContract,
        address _token,
        uint256 _amount
    ) external;

    function pendingRewards(address _stakingContract) external view returns (uint256);

    function poolBalance(address _stakingContract) external view returns (uint256);

    function claimReward(address _stakingContract) external;

    function approveStrategy(address _stakingContract, address _strategy) external;
}
