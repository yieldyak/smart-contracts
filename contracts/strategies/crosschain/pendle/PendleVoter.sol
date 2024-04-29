// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../../lib/Ownable.sol";

import "./interfaces/IPendleVoter.sol";

contract PendleVoter is IPendleVoter, Ownable {
    address public proxy;

    modifier onlyProxy() {
        require(msg.sender == proxy, "PendleVoter::onlyProxy");
        _;
    }

    constructor(address _owner) {
        transferOwnership(_owner);
    }

    function setProxy(address _proxy) external override onlyOwner {
        proxy = _proxy;
    }

    function execute(address target, uint256 value, bytes calldata data)
        external
        override
        onlyProxy
        returns (bool, bytes memory)
    {
        (bool success, bytes memory result) = target.call{value: value}(data);

        return (success, result);
    }
}
