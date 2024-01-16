// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IIncentivesController {
    function rewardMinter() external view returns (address);
    function claimableReward(address _user, address[] memory _tokens) external view returns (uint256[] memory);
    function claim(address _user, address[] memory _tokens) external;
}
