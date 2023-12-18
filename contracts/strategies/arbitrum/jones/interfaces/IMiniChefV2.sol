// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IMiniChefV2 {
    function SUSHI() external view returns (address);

    function incentivesOn() external view returns (bool);

    function poolInfo(uint256 _pid)
        external
        view
        returns (uint128 accSushiPerShare, uint64 lastRewardTime, uint64 allocPoint, uint256 depositIncentives);

    function incentiveReceiver() external view returns (address);

    function deposit(uint256 _pid, uint256 _amount, address _to) external;

    function withdraw(uint256 _pid, uint256 _amount, address _to) external;

    function emergencyWithdraw(uint256 _pid, address _to) external;

    function pendingSushi(uint256 _pid, address _user) external view returns (uint256);

    function harvest(uint256 _pid, address _to) external;

    function userInfo(uint256 pid, address user) external view returns (uint256 amount, uint256 rewardDebt);
}
