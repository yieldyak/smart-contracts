// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface ISingleStaking {
    function balanceOf(address account) external view returns (uint256);
    function earned(address account, address _rewardsToken) external view returns (uint256);
    function stake(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function getReward() external;
}
