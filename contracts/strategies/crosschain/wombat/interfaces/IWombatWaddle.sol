// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IWombatWaddle {
    struct Breeding {
        uint48 unlockTime;
        uint104 womAmount;
        uint104 veWomAmount;
    }

    struct UserInfo {
        // reserve usage for future upgrades
        uint256[10] reserved;
        Breeding[] breedings;
    }

    function mint(uint256 amount, uint256 lockDays) external;

    function update(uint256 slot, uint256 lockDays) external;

    function getUserInfo(address addr) external view returns (UserInfo memory);

    function wom() external view returns (address);
}
