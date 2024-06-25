// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IRebalancePool {
    function rewardManager(address _reward) external view returns (address);
    function extraRewardsLength() external view returns (uint256);
    function extraRewards(uint256 _index) external view returns (address);
    function baseRewardToken() external view returns (address);
    function balanceOf(address _account) external view returns (uint256);
    function claimable(address _account, address _token) external view returns (uint256);
    function deposit(uint256 _amount, address _recipient) external;
    function unlock(uint256 _amount) external;
    function withdrawUnlocked(bool _doClaim, bool _unwrap) external;
    function claim(address[] memory _token, bool _unwrap) external;
    function unlockDuration() external view returns (uint256);
}
