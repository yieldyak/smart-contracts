// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "../lib/Ownable.sol";
import "../lib/SafeMath.sol";
import "../lib/ReentrancyGuard.sol";
import "../interfaces/IYakStrategy.sol";
import "../interfaces/IERC20.sol";

contract RecoverFundsAVAX is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    IYakStrategy public strategy;
    uint256 public recoveredFunds;
    uint256 public totalSupply;
    uint256 public ownerRecoveryLock;

    event Recovered(
        uint256 depositTokenAmount,
        address receiptToken,
        uint256 receiptTokenAmount
    );

    constructor(address _owner, address _strategy) payable nonReentrant {
        strategy = IYakStrategy(_strategy);
        totalSupply = strategy.totalSupply();
        recoveredFunds = msg.value;
        ownerRecoveryLock = block.timestamp + 14 days;
        transferOwnership(_owner);
    }

    receive() external payable {
        require(
            msg.sender == address(strategy) || msg.sender == owner(),
            "Avax deposit not allowed"
        );
    }

    function withdraw(uint256 amount) external nonReentrant {
        if (amount > strategy.balanceOf(msg.sender)) {
            amount = strategy.balanceOf(msg.sender);
        }

        require(amount > 0, "not funds");

        uint256 recoveredAmount = recoveredFunds.mul(amount).div(totalSupply);

        // transfers the receipt tokens to this contract
        require(
            strategy.transferFrom(msg.sender, address(this), amount),
            "transferFrom YRT failed"
        );
        // transfers the deposit tokens back to their owner
        (bool success, ) = msg.sender.call{value: recoveredAmount}("");
        require(success, "transfer failed");

        emit Recovered(recoveredAmount, address(strategy), amount);
    }

    /**
     * @notice Recover ERC20 from contract
     * @param tokenAddress token address
     * @param tokenAmount amount to recover
     */
    function recoverERC20(address tokenAddress, uint256 tokenAmount)
        external
        onlyOwner
    {
        require(tokenAmount > 0);
        require(
            block.timestamp > ownerRecoveryLock,
            "functionality only unlocked after 14 days"
        );
        require(IERC20(tokenAddress).transfer(msg.sender, tokenAmount));
        emit Recovered(tokenAmount, address(strategy), 0);
    }

    /**
     * @notice Recover AVAX from contract
     * @param amount amount
     */
    function recoverAVAX(uint256 amount) external onlyOwner {
        require(amount > 0);
        require(
            block.timestamp > ownerRecoveryLock,
            "functionality only unlocked after 14 days"
        );
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "transfer failed");
        emit Recovered(amount, address(strategy), 0);
    }
}
