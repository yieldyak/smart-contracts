// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IMuxRewardRouter {
    function stakedMlpAmount(address _account) external view returns (uint256);
    function stakeMlp(uint256 _amount) external;
    function unstakeMlp(uint256 _amount) external;
    function mlpFeeTracker() external view returns (address);
    function votingEscrow() external view returns (address);
    function vault() external view returns (address);
    function claimAll() external;
}
