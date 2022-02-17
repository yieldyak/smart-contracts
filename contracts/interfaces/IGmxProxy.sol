// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

interface IGmxProxy {
    function gmxDepositor() external view returns (address);

    function gmxRewardRouter() external view returns (address);

    function buyAndStakeGlp(uint256 _amount) external returns (uint256);

    function withdrawGlp(uint256 _amount) external;

    function stakeGmx(uint256 _amount) external;

    function withdrawGmx(uint256 _amount) external;

    function claimReward(address _rewardTracker) external;

    function depositorBalance(address _token) external view returns (uint256);

    function emergencyWithdrawGLP(uint256 _balance) external;

    function emergencyWithdrawGMX(uint256 _balance) external;
}
