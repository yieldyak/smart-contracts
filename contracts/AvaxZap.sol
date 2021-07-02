// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "./interfaces/IWAVAX.sol";
import "./lib/Ownable.sol";
import "./lib/SafeMath.sol";

/**
 * @notice 
 * @dev Assumes User already sent AVAX to this contract and this contract is being executed from a strategy Contract
 */
contract AvaxZap is Ownable {
    using SafeMath for uint;
    address public WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    bytes private constant zeroBytes = new bytes(0);
    event Received(address,uint);
    event Deposit(address, uint);
    event Withdraw(address, uint);

    constructor () {}

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    function _depositAVAX(address strategyContract, uint amountAVAX) external payable {
        require(payable(address(this)).balance > amountAVAX );
        IWAVAX(WAVAX).deposit{value: amountAVAX}();
        require(IWAVAX(WAVAX).transfer(address(strategyContract), amountAVAX));
        emit Deposit(strategyContract, amountAVAX);
    }
    

/**
     * @notice Safely transfer AVAX
     * @dev Requires token to return true on transfer
     * @param to recipient address
     * @param intValue amount
     */
    function _safeTransferAVAX(address payable to, uint256 intValue) internal {
        (bool success, ) = to.call{value: intValue}(zeroBytes);
        require(success, 'TransferHelper: AVAX_TRANSFER_FAILED');
    }

    function withdrawAVAX(uint amountAVAX) external {
        if (amountAVAX > 0) {
            IWAVAX(WAVAX).withdraw(amountAVAX);
            _safeTransferAVAX(msg.sender, amountAVAX);
            emit Withdraw(msg.sender, amountAVAX);
        }
    }

}