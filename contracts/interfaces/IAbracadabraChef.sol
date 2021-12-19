// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

interface IAbracadabraChef {
    function deposit(uint256 _pid, uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function emergencyWithdraw(uint256 _pid) external;

    function pendingIce(uint256 _pid, address _user) external view returns (uint256);

    function userInfo(uint256 _pid, address _user)
        external
        view
        returns (
            uint256 amount,
            uint256 rewardDebt,
            uint256 remainingIceTokenReward
        );
}
