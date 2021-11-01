// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

// https://github.com/Benqi-fi/BENQI-Smart-Contracts/blob/master/staking/PglStakingContract.sol
interface IBenqiStakingContract {
    function setRewardSpeed(uint256 rewardToken, uint256 speed) external;

    function supplyAmount(address) external view returns (uint256);

    function deposit(uint256 pglAmount) external;

    function redeem(uint256 pglAmount) external;

    function claimRewards() external;

    function getClaimableRewards(uint256 rewardToken) external view returns (uint256);
}
