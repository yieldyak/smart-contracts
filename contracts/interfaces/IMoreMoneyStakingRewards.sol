// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

interface IMoreMoneyStakingRewards {
    function vested(address account) external view returns (uint256);

    function stake(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function withdrawVestedReward() external;

    function balanceOf(address account) external view returns (uint256);

    function exit() external;
}
