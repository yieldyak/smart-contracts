// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IBoostedMasterWombat {
    function getAssetPid(address _asset) external view returns (uint256);

    function deposit(uint256 _pid, uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function emergencyWithdraw(uint256 _pid) external;

    function userInfo(uint256 _pid, address _user) external view returns (uint128, uint128, uint128, uint128);

    function pendingTokens(uint256 _pid, address _user)
        external
        view
        returns (
            uint256 pendingRewards,
            address[] memory bonusTokenAddresses,
            string[] memory bonusTokenSymbols,
            uint256[] memory pendingBonusRewards
        );
}
