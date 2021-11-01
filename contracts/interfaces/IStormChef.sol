// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface IStormChef {
    function userInfo(uint256 pid, address user) external view returns (uint256 amount, uint256 rewardDebt);

    function poolInfo(uint256 pid)
        external
        view
        returns (
            address lpToken,
            uint256 allocPoint,
            uint256 lastRewardBlock,
            uint256 accStormPerShare,
            uint16 withdrawFeeBP,
            uint256 lpSupply
        );

    // View function to see pending Stormes on frontend.
    function pendingStorm(uint256 _pid, address _user) external view returns (uint256);

    // Deposit LP tokens to MasterChef for Storm allocation.
    function deposit(
        uint256 _pid,
        uint256 _amount,
        address _referrer
    ) external;

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) external;

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external;
}
