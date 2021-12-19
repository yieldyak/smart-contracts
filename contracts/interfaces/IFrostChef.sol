// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

interface IFrostChef {
    function TUNDRA() external view returns (address);
    function TUNDRAPerBlock() external view returns (uint256);

    function poolLength() external view returns (uint256);
    function pendingTUNDRA(uint256 _pid, address _user) external view returns (uint256);
    function updatePool(uint256 _pid) external;
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function emergencyWithdraw(uint256 _pid) external;
    function poolInfo(uint pid) external view returns (
        address lpToken,
        uint allocPoint,
        uint lastRewardBlock,
        uint accTUNDRAPerShare,
        uint16 withdrawFeeBP
    );
    function userInfo(uint pid, address user) external view returns (
        uint256 amount,
        uint256 rewardDebt
    );
}