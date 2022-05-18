// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IKyberFairLaunchV2 {
    function deposit(
        uint256 _pid,
        uint256 _amount,
        bool _shouldHarvest
    ) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function pendingRewards(uint256 _pid, address _user) external view returns (uint256[] memory rewards);

    function getRewardTokens() external view returns (address[] memory);

    function getUserInfo(uint256 _pid, address _account)
        external
        view
        returns (
            uint256 amount,
            uint256[] memory unclaimedRewards,
            uint256[] memory lastRewardPerShares
        );

    function harvest(uint256 _pid) external;

    function rewardLocker() external returns (address);

    function emergencyWithdraw(uint256 _pid) external;
}
