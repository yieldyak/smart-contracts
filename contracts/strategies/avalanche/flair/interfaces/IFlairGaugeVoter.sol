// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IFlairGaugeVoter {
    function vote(uint256 tokenId, address[] calldata _poolVote, int256[] calldata _weights) external;
    function claimFees(address[] memory _bribes, address[][] memory _tokens, uint256 _tokenId) external;
}
