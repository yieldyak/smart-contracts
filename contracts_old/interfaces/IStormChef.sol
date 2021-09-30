// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface IStormChef {
    function userInfo(uint pid, address user) external view returns (
        uint256 amount,
        uint256 rewardDebt
    );

    function poolInfo(uint pid) external view returns (
        address lpToken,
        uint allocPoint,
        uint lastRewardBlock,
        uint accStormPerShare,
        uint16 withdrawFeeBP,
        uint lpSupply
    );

    // View function to see pending Stormes on frontend.
    function pendingStorm(uint256 _pid, address _user) external view returns (uint256);

    // Deposit LP tokens to MasterChef for Storm allocation.
    function deposit(uint256 _pid, uint256 _amount, address _referrer) external;

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) external;

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external;
}