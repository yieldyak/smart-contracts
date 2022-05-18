// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../lib/Ownable.sol";

import "./interfaces/IGmxDepositor.sol";

contract GmxDepositor is IGmxDepositor, Ownable {
    address public proxy;

    modifier onlyGmxProxy() {
        require(msg.sender == proxy, "GmxDepositor::onlyGmxProxy");
        _;
    }

    constructor(address _owner) {
        transferOwnership(_owner);
    }

    function setGmxProxy(address _proxy) external override onlyOwner {
        proxy = _proxy;
    }

    function execute(
        address target,
        uint256 value,
        bytes calldata data
    ) external override onlyGmxProxy returns (bool, bytes memory) {
        (bool success, bytes memory result) = target.call{value: value}(data);

        return (success, result);
    }
}
