// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../interfaces/IERC20.sol";
import "./interfaces/IJoeVoterProxy.sol";

/**
 * @notice TransferHelper moves stuck AVAX from JoeVoter to `RECEIVER`.
 * The contract re-uses `devAddr` from JoeVoterProxy, which can disable
 * transfers and change `RECEIVER`. While the contract is not disabled,
 * anyone can call `transfer()`.
 * 
 * This TransferHelper should be disabled and upgraded in case more than
 * one Strategy awards AVAX to JoeVoter or JoeVoterProxy is upgraded.
 */
contract TransferHelper {
    uint256 public constant PID = 0;
    address public constant STAKING_CONTRACT = address(0);
    IJoeVoterProxy public constant PROXY = IJoeVoterProxy(0xc31e24f8A25a1dCeCcfd791CA25b62dcFec5c8F7);
    address public RECEIVER;
    bool public DISABLED;

    address private constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;

    constructor() {
        RECEIVER = msg.sender;
    }

    /**
     * @notice Claims AVAX/WAVAX from `PROXY` and transfers balance to `RECEIVER`
     * @dev Restricted to EOA
     */
    function transfer() external {
        require(!DISABLED, "TransferHelper::disabled");
        require(msg.sender == tx.origin, "TransferHelper::onlyEOA");
        PROXY.distributeReward(PID, STAKING_CONTRACT, WAVAX);
        uint256 amount = IERC20(WAVAX).balanceOf(address(this));
        if (amount > 0) {
            IERC20(WAVAX).transfer(RECEIVER, amount);
        }
    }

    /**
     * @notice Reads `devAddr` from `PROXY`
     * @dev Admin rights are inherited from `PROXY`
     * @return address devAddr
     */
    function devAddr() view public returns (address) {
        return PROXY.devAddr();
    }

    /**
     * @notice Disable the contract functionality
     * @dev Restricted to `devAddr`
     * @dev One-way change; contract cannot be subsequently enabled
     */
    function disable() external {
        require(msg.sender == devAddr(), "TransferHelper::onlyDev");
        DISABLED = true;
    }

    function updateReceiver(address receiver) external {
        require(msg.sender == devAddr(), "TransferHelper::onlyDev");
        RECEIVER = receiver;
    }
}
