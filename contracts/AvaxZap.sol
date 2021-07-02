// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "./interfaces/IWAVAX.sol";
import "./lib/Ownable.sol";
import "./lib/SafeMath.sol";
import "./YakStrategy.sol";

/**
 * @notice 
 * @dev Assumes User send AVAX to this contract in value of the payable method
 */
contract AvaxZap is Ownable {
    using SafeMath for uint;
    address public WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    bytes private constant zeroBytes = new bytes(0);
    event Received(address,uint);

    constructor () {}

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    function _depositAVAX(address strategyContract) external payable {
        require(payable(address(this)).balance > msg.value );
        IWAVAX(WAVAX).deposit{value: msg.value}();
        IWAVAX(WAVAX).approve(strategyContract, msg.value);
        require(YakStrategy(strategyContract).depositToken.address == address(WAVAX));
        YakStrategy(strategyContract).depositFor(msg.sender, msg.value);
    }

    function Withdraw(address strategyContract, uint amountAVAX) external {
            YakStrategy(strategyContract).withdraw(amountAVAX);
    }

}