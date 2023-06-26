// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface ILevelMasterV2 {
    function pendingReward(uint256 _pid, address _user) external view returns (uint256 pending);
    function deposit(uint256 pid, uint256 amount, address to) external;
    function withdraw(uint256 pid, uint256 amount, address to) external;
    function harvest(uint256 pid, address to) external;
    function addLiquidity(uint256 pid, address assetToken, uint256 assetAmount, uint256 minLpAmount, address to)
        external;
    function userInfo(uint256 pid, address user) external view returns (uint256 amount, uint256 rewardDebt);
    function levelPool() external view returns (address);
}
