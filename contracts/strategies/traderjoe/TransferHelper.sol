// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../interfaces/IERC20.sol";
import "./interfaces/IJoeVoterProxy.sol";

contract TransferHelper {
    uint256 public constant PID = 0;
    IJoeVoterProxy public constant PROXY = IJoeVoterProxy(0xc31e24f8A25a1dCeCcfd791CA25b62dcFec5c8F7);
    address public constant RECEIVER = 0x1A43031783b7E042fa971092843fb4D75620df63;
    address public constant STAKING_CONTRACT = address(0);

    address private constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;

    function transfer() external {
        PROXY.distributeReward(PID, STAKING_CONTRACT, WAVAX);
        uint256 amount = IERC20(WAVAX).balanceOf(address(this));
        if (amount > 0) {
            IERC20(WAVAX).transfer(RECEIVER, amount);
        }
    }
}
