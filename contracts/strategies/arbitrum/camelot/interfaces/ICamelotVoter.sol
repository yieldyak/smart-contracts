// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface ICamelotVoter {
    function execute(
        address to,
        uint256 value,
        bytes calldata data
    ) external returns (bool, bytes memory);

    function wrapEthBalance() external returns (uint256);

    function depositsEnabled() external view returns (bool);

    function deposit(uint256 _amount) external;

    function depositFromBalance(uint256 _value) external;

    function unallocatedXGrail() external view returns (uint256);

    function allocatedXGrail() external view returns (uint256);

    function setVoterProxy(address _voterProxy) external;
}
