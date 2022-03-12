// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

import "./IPlatypusVoter.sol";

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

    function deposit(
        uint256 _pid,
        address _stakingContract,
        address _pool,
        address _token,
        address _asset,
        uint256 _amount,
        uint256 _depositFee
    ) external;

    function pendingRewards(address _stakingContract, uint256 _pid)
        external
        view
        returns (
            uint256,
            uint256,
            address
        );

    function poolBalance(address _stakingContract, uint256 _pid) external view returns (uint256);

    function platypusVoter() external view returns (IPlatypusVoter);

    function claimReward(address _stakingContract, uint256 _pid) external;

    function approveStrategy(address _strategy) external;

    function reinvestFeeBips() external view returns (uint256);

    function migrateMasterPlatypus(
        address _masterPlatypus,
        uint256 _masterPlatypusVersion,
        uint256[] memory _pids
    ) external;
}
