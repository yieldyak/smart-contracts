// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "./interfaces/IWAVAX.sol";
import "./lib/Ownable.sol";
import "./lib/SafeMath.sol";
import "./YakStrategy.sol";

/**
 * @notice 
 * @dev Assumes User send AVAX to this contract in value of the payable deposit method
 */
contract AvaxZap is Ownable {
    using SafeMath for uint;
    address public WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    event Received(address,uint);
    event Recovered(address token, uint amount);

    constructor (
        address _timelock
    ) {
        transferOwnership(_timelock);
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    function _depositAVAX(address strategyContract) external payable {
        IWAVAX(WAVAX).deposit{value: msg.value}();
        IWAVAX(WAVAX).approve(strategyContract, msg.value);
        require(address(YakStrategy(strategyContract).depositToken()) == address(WAVAX));
        YakStrategy(strategyContract).depositFor(msg.sender, msg.value);
    }

    /**
   * @notice Recover AVAX from contract
   * @param amount amount
   */
  function recoverAVAX(uint amount) external onlyOwner {
    require(amount > 0, 'amount too low');
    msg.sender.transfer(amount);
    emit Recovered(address(0), amount);
  }

}