// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./../../../BaseStrategy.sol";

interface IWombatProxy {
    function voter() external view returns (address);
    function depositToStakingContract(address _masterWombat, uint256 _pid, address _token, uint256 _amount) external;
    function withdrawFromStakingContract(address _masterWombat, uint256 _pid, address _token, uint256 _amount)
        external;
    function emergencyWithdraw(address _masterWombat, uint256 _pid, address _token) external;
    function pendingRewards(address _masterWombat, uint256 _pid) external view returns (BaseStrategy.Reward[] memory);
    function getRewards(address _masterWombat, uint256 _pid) external;
    function totalDeposits(address _masterWombat, uint256 _pid) external view returns (uint256);
}
