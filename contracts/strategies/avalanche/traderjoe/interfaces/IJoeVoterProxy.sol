// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IJoeVoterProxy {
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

    function pendingRewards(address _stakingContract, uint256 _pid)
        external
        view
        returns (
            uint256,
            address,
            uint256
        );

    function poolBalance(address _stakingContract, uint256 _pid) external view returns (uint256);

    function claimReward(
        uint256 _pid,
        address _stakingContract,
        address _extraToken
    ) external;

    function distributeReward(
        uint256 _pid,
        address _stakingContract,
        address _extraToken
    ) external;

    function approveStrategy(address _stakingContract, address _strategy) external;

    function reinvestFeeBips() external view returns (uint256);
}
