// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IWombexRewardPool {
    function claimableRewards(address _account)
        external
        view
        returns (address[] memory tokens, uint256[] memory amounts);
    function balanceOf(address account) external view returns (uint256);
    function getReward() external returns (bool);
    function asset() external view returns (address);
    function withdrawAndUnwrap(uint256 amount, bool claim) external;
    function withdrawAllAndUnwrap(bool claim) external;
}
