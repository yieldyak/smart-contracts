// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface IBirdyChef {
    function bird() external view returns (address);

    function birdPerBlock() external view returns (uint256);

    function poolLength() external view returns (uint256);

    function pendingBIRD(uint256 _pid, address _user) external view returns (uint256);

    function deposit(uint256 _pid, uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function emergencyWithdraw(uint256 _pid) external;

    function poolInfo(uint256 pid)
        external
        view
        returns (
            address lpToken,
            uint256 allocPoint,
            uint256 lastRewardBlock,
            uint256 accBIRDPerShare,
            uint16 withdrawFeeBP
        );

    function userInfo(uint256 pid, address user) external view returns (uint256 amount, uint256 rewardDebt);
}
