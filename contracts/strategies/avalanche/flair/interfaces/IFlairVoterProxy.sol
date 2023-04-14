// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../interfaces/IFlairVoter.sol";
import "./../../../VariableRewardsStrategy.sol";

interface IFlairVoterProxy {
    function voter() external returns (IFlairVoter);
    function deposit(address _gauge, address _token, uint256 _amount) external;
    function withdraw(address _gauge, address _token, uint256 _amount) external;
    function pendingRewards(address _gauge, address[] memory _tokens, bool _claimBribes)
        external
        view
        returns (VariableRewardsStrategy.Reward[] memory);
    function getRewards(address _gauge, address[] memory _tokens, bool _claimBribes) external;
    function totalDeposits(address _gauge) external view returns (uint256);
    function emergencyWithdraw(address _gauge, address _token) external;
}
