// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IMasterChef {
    function claim(uint256[] memory pids) external;

    function deposit(uint256 pid, uint256 amount) external;

    function withdraw(uint256 pid, uint256 amount) external;

    function emergencyWithdraw(uint256 pid) external;

    function getDeposit(uint256 pid, address account) external view returns (uint256);

    function getLastUpdateTimestamp(uint256 pid) external view returns (uint256);

    function getPendingRewards(address account, uint256[] memory pids)
        external
        view
        returns (uint256[] memory moeRewards, address[] memory extraTokens, uint256[] memory extraRewards);

    function getExtraRewarder(uint256 pid) external view returns (address);

    function getMoe() external view returns (address);
}
