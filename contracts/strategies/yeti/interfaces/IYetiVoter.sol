// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./IVeYeti.sol";

interface IYetiVoter {
    function execute(
        address to,
        uint256 value,
        bytes calldata data
    ) external returns (bool, bytes memory);

    function depositFromBalance(uint256 _amount, IVeYeti.RewarderUpdate[] memory _rewarderUpdates) external;

    function updateVeYeti(IVeYeti.RewarderUpdate[] memory _rewarderUpdates) external;

    function depositsEnabled() external view returns (bool);
}
