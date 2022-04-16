// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

interface IEchidnaVoterProxy {
    function withdraw(
        uint256 _pid,
        address _stakingContract,
        address _token,
        uint256 _amount
    ) external;

    function emergencyWithdraw(
        uint256 _pid,
        address _stakingContract,
        address _token
    ) external;

    function deposit(
        uint256 _pid,
        address _stakingContract,
        address _token,
        uint256 _amount
    ) external;

    function pendingRewards(address _stakingContract, uint256 _pid) external view returns (uint256, uint256);

    function poolBalance(address _stakingContract, uint256 _pid) external view returns (uint256);

    function claimReward(address _stakingContract, uint256 _pid) external;

    function distributeReward(address _stakingContract, uint256 _pid) external;

    function approveStrategy(address _stakingContract, address _strategy) external;
}
