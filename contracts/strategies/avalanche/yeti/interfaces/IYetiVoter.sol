// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IYetiVoter {
    function execute(
        address to,
        uint256 value,
        bytes calldata data
    ) external returns (bool, bytes memory);

    function depositFromBalance(uint256 _amount) external;

    function depositsEnabled() external view returns (bool);
}
