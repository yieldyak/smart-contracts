// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IVotingGauge {
    function vote(address[] calldata _lpVote, int256[] calldata _deltas)
        external
        returns (uint256[] memory bribeRewards);

    function bribes(address _lpToken) external view returns (address);
}
