// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IGlacierGaugeVoter {
    function vote(uint256 tokenId, address[] calldata _poolVote, uint256[] calldata _weights) external;
}
