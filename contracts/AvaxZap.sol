// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./interfaces/IWAVAX.sol";
import "./interfaces/IYakStrategy.sol";
import "./interfaces/IERC20.sol";
import "./lib/Ownable.sol";

/**
 * @notice Zap AVAX into strategies with WAVAX deposit token
 */
contract AvaxZap is Ownable {
    address private constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;

    event Recovered(address token, uint256 amount);

    receive() external payable {}

    /**
     * @notice Deposit wavax to the contract on behalf of user
     * @param strategyContract strategy contract address
     */
    function depositAVAX(address strategyContract) external payable {
        IWAVAX(WAVAX).deposit{value: msg.value}();
        IWAVAX(WAVAX).approve(strategyContract, msg.value);
        require(IYakStrategy(strategyContract).depositToken() == WAVAX, "AvaxZap::depositAvax incompatible strategy");
        IYakStrategy(strategyContract).depositFor(msg.sender, msg.value);
    }

    /**
     * @notice Recover ERC20 from contract
     * @param tokenAddress token address
     * @param tokenAmount amount to recover
     */
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        require(tokenAmount > 0, "amount too low");
        require(IERC20(tokenAddress).transfer(msg.sender, tokenAmount));
        emit Recovered(tokenAddress, tokenAmount);
    }

    /**
     * @notice Recover AVAX from contract
     * @param amount amount
     */
    function recoverAVAX(uint256 amount) external onlyOwner {
        require(amount > 0, "amount too low");
        payable(msg.sender).transfer(amount);
        emit Recovered(address(0), amount);
    }
}
