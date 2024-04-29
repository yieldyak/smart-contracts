// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./../../../BaseStrategy.sol";

interface IPendleProxy {
    function voter() external view returns (address);
    function depositToStakingContract(address _token, uint256 _amount) external;
    function withdrawFromStakingContract(address _token, uint256 _amount) external;
    function emergencyWithdraw(address _token) external;
    function pendingRewards(address _token) external view returns (BaseStrategy.Reward[] memory);
    function getRewards(address _token) external;
    function totalDeposits(address _token) external view returns (uint256);
}
