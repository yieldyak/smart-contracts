// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

interface IJoeVoter {
    function execute(
        address to,
        uint256 value,
        bytes calldata data
    ) external returns (bool, bytes memory);

    function veJOEBalance() external view returns (uint256);

    function wrapAvaxBalance() external returns (uint256);

    function depositsEnabled() external view returns (bool);

    function depositFromBalance(uint256 _value) external;

    function setStakingContract(address _stakingContract) external;

    function setVoterProxy(address _voterProxy) external;

    function claimVeJOE() external;
}
