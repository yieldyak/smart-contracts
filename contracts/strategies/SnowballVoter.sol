// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../interfaces/IGauge.sol";
import "../interfaces/IVoteEscrow.sol";
import "../lib/Ownable.sol";

contract SnowballVoter is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    
    address constant public snob = address(0xC38f41A296A4493Ff429F1238e030924A1542e50);
    address constant public escrow = address(0x83952E7ab4aca74ca96217D6F8f7591BEaD6D64E);

    address public immutable devAddr;
    address public snowballProxy;
    
    constructor(address _timelock) {
        devAddr = msg.sender;
        transferOwnership(_timelock);
    }
    
    function getName() external pure returns (string memory) {
        return "SnowballVoter";
    }
    
    function setSnowballProxy(address _snowballProxy) external onlyOwner {
        snowballProxy = _snowballProxy;
    }
    
    function withdraw(uint _amount) external {
        require(msg.sender == snowballProxy, "!snowballProxy");
        IERC20(snob).safeTransfer(snowballProxy, _amount);
    }
    
    function withdrawAll() external returns (uint balance) {
        require(msg.sender == snowballProxy, "!snowballProxy");
        balance = IERC20(snob).balanceOf(address(this));
        IERC20(snob).safeTransfer(snowballProxy, balance);
    }
    
    function createLock(uint _value, uint _unlockTime) external {
        require(msg.sender == snowballProxy || msg.sender == devAddr, "!authorized");
        IERC20(snob).safeApprove(escrow, 0);
        IERC20(snob).safeApprove(escrow, _value);
        IVoteEscrow(escrow).create_lock(_value, _unlockTime);
    }
    
    function increaseAmount(uint _value) external {
        require(msg.sender == snowballProxy || msg.sender == devAddr, "!authorized");
        IERC20(snob).safeApprove(escrow, 0);
        IERC20(snob).safeApprove(escrow, _value);
        IVoteEscrow(escrow).increase_amount(_value);
    }

    function increaseUnlockTime(uint _unlockTime) external {
        require(msg.sender == snowballProxy || msg.sender == devAddr, "!authorized");
        IVoteEscrow(escrow).increase_unlock_time(_unlockTime);
    }
    
    function release() external {
        require(msg.sender == snowballProxy || msg.sender == devAddr, "!authorized");
        IVoteEscrow(escrow).withdraw();
    }
    
    function balanceOfSnob() public view returns (uint) {
        return IERC20(snob).balanceOf(address(this));
    }
    
    function execute(address target, uint value, bytes calldata data) external returns (bool, bytes memory) {
        require(msg.sender == snowballProxy, "!authorized");
        (bool success, bytes memory result) = target.call{value: value}(data);
        
        return (success, result);
    }
}