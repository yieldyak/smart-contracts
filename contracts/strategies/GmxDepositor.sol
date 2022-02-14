// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

import "../interfaces/IWAVAX.sol";
import "../lib/SafeERC20.sol";
import "../lib/Ownable.sol";

contract GmxDepositor is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IWAVAX private constant WAVAX = IWAVAX(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);

    address public proxy;

    modifier onlyGmxProxy() {
        require(msg.sender == proxy, "GmxDepositor::onlyGmxProxy");
        _;
    }

    constructor(address _timelock) {
        transferOwnership(_timelock);
    }

    function setProxy(address _proxy) external onlyOwner {
        proxy = _proxy;
    }

    function execute(
        address target,
        uint256 value,
        bytes calldata data
    ) external onlyGmxProxy returns (bool, bytes memory) {
        (bool success, bytes memory result) = target.call{value: value}(data);

        return (success, result);
    }
}
