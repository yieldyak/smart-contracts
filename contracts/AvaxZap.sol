// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "./interfaces/IWAVAX.sol";
import "./lib/Ownable.sol";
import "./lib/SafeMath.sol";
import "./interfaces/IYakStrategy.sol";

/**
 * @notice
 * @dev Assumes User send AVAX to this contract in value of the payable deposit method
 */
contract AvaxZap is Ownable {
    using SafeMath for uint256;
    address public WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    event Recovered(address token, uint256 amount);

    constructor(address _timelock) {
        transferOwnership(_timelock);
    }

    /**
     * @notice deposit wavax to the contract on behalf of user
     * @param strategyContract strategy contract address
     */
    function depositAVAX(address strategyContract) external payable {
        IWAVAX(WAVAX).deposit{value: msg.value}();
        IWAVAX(WAVAX).approve(strategyContract, msg.value);
        require(address(IYakStrategy(strategyContract).depositToken()) == address(WAVAX));
        IYakStrategy(strategyContract).depositFor(msg.sender, msg.value);
    }

    /**
     * @notice Recover AVAX from contract
     * @param amount amount
     */
    function recoverAVAX(uint256 amount) external onlyOwner {
        require(amount > 0, "amount too low");
        msg.sender.transfer(amount);
        emit Recovered(address(0), amount);
    }
}
