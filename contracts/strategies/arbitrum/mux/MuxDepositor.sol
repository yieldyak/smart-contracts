// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../../lib/Ownable.sol";

import "./interfaces/IMuxDepositor.sol";

contract MuxDepositor is IMuxDepositor, Ownable {
    address internal constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    address public proxy;

    modifier onlyMuxProxy() {
        require(msg.sender == proxy, "MuxDepositor::onlyMuxProxy");
        _;
    }

    constructor(address _owner) {
        transferOwnership(_owner);
    }

    receive() external payable {
        require(msg.sender == address(WETH), "not allowed");
    }

    function setMuxProxy(address _proxy) external override onlyOwner {
        proxy = _proxy;
    }

    function execute(address target, uint256 value, bytes calldata data)
        external
        override
        onlyMuxProxy
        returns (bool, bytes memory)
    {
        (bool success, bytes memory result) = target.call{value: value}(data);

        return (success, result);
    }
}
