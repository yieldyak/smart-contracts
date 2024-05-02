// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./../../../BaseStrategy.sol";

interface IPendleProxy {
    function voter() external view returns (address);
    function depositToStakingContract(address _market, uint256 _amount) external;
    function withdrawFromStakingContract(address _market, uint256 _amount) external;
    function emergencyWithdraw(address _market) external;
    function pendingRewards(address _market) external view returns (BaseStrategy.Reward[] memory);
    function getRewards(address _market) external;
    function totalDeposits(address _market) external view returns (uint256);
}
