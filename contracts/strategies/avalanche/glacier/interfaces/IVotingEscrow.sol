// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IVotingEscrow {
    struct LockedBalance {
        int128 amount;
        uint256 end;
    }

    function create_lock(uint256 _value, uint256 _lock_duration) external returns (uint256);
    function increase_amount(uint256 _tokenId, uint256 _value) external;
    function increase_unlock_time(uint256 _tokenId, uint256 _lock_duration) external;
    function balanceOf(address account) external view returns (uint256);
    function locked(uint256 tokenId) external view returns (LockedBalance memory);
    function withdraw(uint256 _tokenId) external;
}
