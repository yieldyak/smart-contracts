// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

interface IBoosterFeeCollector {
    function setBoostFee(address _strategy, uint256 _boostFeeBips) external;

    function setBoosterFeeReceiver(address _boosterFeeReceiver) external;

    function setPaused(bool _paused) external;

    function calculateBoostFee(address _strategy, uint256 _amount) external view returns (uint256);

    function compound() external;
}
