// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

interface IPlatypusVoter {
    function execute(
        address to,
        uint256 value,
        bytes calldata data
    ) external returns (bool, bytes memory);

    function wrapAvaxBalance() external returns (uint256);

    function depositsEnabled() external returns (bool);

    function depositFromBalance(uint256 _value) external;

    function setVoterProxy(address _voterProxy) external;
}
