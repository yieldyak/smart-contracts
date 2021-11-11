//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "../lib/SafeMath.sol";
import "../lib/Ownable.sol";
import "../lib/AccessControl.sol";

import "hardhat/console.sol";

contract FeePayer is AccessControl {
    using SafeMath for uint256;
    /// @notice Role that owns the contract, can add and remove other members to roles
    bytes32 public constant ADMIN = keccak256("ADMIN");

    /// @notice Role that allows members to ask for fees
    bytes32 public constant FEE_PAYEE = keccak256("FEE_PAYEE");

    /// @notice Role that allows members to whitelist members as FEE_PAYEE
    bytes32 public constant WHITELISTER = keccak256("WHITELISTER");

    mapping(address => uint256) public payeesToBounties;

    constructor() {
        _setupRole(ADMIN, msg.sender);
        _setupRole(WHITELISTER, msg.sender);
        _setRoleAdmin(FEE_PAYEE, WHITELISTER);
        _setRoleAdmin(WHITELISTER, ADMIN);
    }

    function addFeePayee(address payee, uint256 reward) external {
        require(hasRole(WHITELISTER, msg.sender), "Only Whitelister allowed");
        grantRole(FEE_PAYEE, payee);
        payeesToBounties[payee] = reward;
    }

    function PayFee(uint256 feeEstimate, address receiver) external {
        require(hasRole(FEE_PAYEE, msg.sender), "Only FeePayee allowed");
        console.log(
            feeEstimate.mul(block.basefee.add(2 gwei)).add(payeesToBounties[msg.sender])
        );
        receiver.call{
            value: feeEstimate.mul(block.basefee.add(2 gwei)).add(
                payeesToBounties[msg.sender]
            )
        }("");
    }
}
