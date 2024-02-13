// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IWombatVoter {
    function execute(address to, uint256 value, bytes calldata data) external returns (bool, bytes memory);

    function setProxy(address _proxy) external;

    function reservedWom() external view returns (uint256);

    function setReservedWom(uint256 _reservedWom) external;
}
