// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

interface IPlatypusVoter {
    function execute(
        address to,
        uint256 value,
        bytes calldata data
    ) external returns (bool, bytes memory);

    function vePTPBalance() external view returns (uint256);

    function wrapAvaxBalance() external returns (uint256);

    function deposit(uint256 _amount) external;

    function depositsEnabled() external view returns (bool);

    function depositFromBalance(uint256 _value) external;

    function setVoterProxy(address _voterProxy) external;

    function claimVePTP() external;
}
