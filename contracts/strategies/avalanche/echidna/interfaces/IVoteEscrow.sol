// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IVoteEscrow {
    function create_lock(uint256, uint256) external;

    function locked(address) external view returns (int128, uint256);

    function balanceOf(address) external view returns (uint256);

    function increase_amount(uint256) external;

    function increase_unlock_time(uint256) external;

    function withdraw() external;
}
