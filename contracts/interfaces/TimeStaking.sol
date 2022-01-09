// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

interface TimeStaking {
  function epoch() external view returns (uint256 number, uint256 distribute, uint32 length, uint32 endTime);
  function stake(uint256 _amount, address _recipient) external returns (bool);
  function unstake(uint256 _amount, bool _trigger) external;
  function claim(address _recipient) external;
  function warmupPeriod() external view returns (uint256);
}