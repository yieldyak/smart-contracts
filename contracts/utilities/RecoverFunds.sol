// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "../lib/Ownable.sol";
import "../lib/SafeMath.sol";
import "../interfaces/IYakStrategy.sol";
import "../interfaces/IERC20.sol";

contract RecoverFunds is Ownable {
    using SafeMath for uint256;
    IERC20 public depositToken;
    IYakStrategy public strategy;
    uint256 public recoveredFunds;
    uint256 public totalSupply;
    uint256 public ownerRecoveryLock;

    event Recovered(
        address depositToken,
        uint256 depositTokenAmount,
        address receiptToken,
        uint256 receiptTokenAmount
    );

    constructor(
        address _owner,
        address _depositToken,
        address _strategy,
        uint256 amountRecovered
    ) {
        depositToken = IERC20(_depositToken);
        strategy = IYakStrategy(_strategy);
        totalSupply = strategy.totalSupply();
        depositToken.transferFrom(msg.sender, address(this), amountRecovered);
        recoveredFunds = amountRecovered;
        ownerRecoveryLock = block.timestamp + 14 days;
        transferOwnership(_owner);
    }

    function withdraw(uint256 amount) external {
        if (amount > strategy.balanceOf(msg.sender)) {
            amount = strategy.balanceOf(msg.sender);
        }

        uint256 recoveredAmount = recoveredFunds.mul(amount).div(totalSupply);

        // transfers the receipt tokens to this contract
        require(
            strategy.transferFrom(msg.sender, address(this), amount),
            "transferFrom YRT failed"
        );
        // transfers the deposit tokens back to their owner
        require(
            depositToken.transfer(msg.sender, recoveredAmount),
            "transfer failed"
        );

        emit Recovered(
            address(depositToken),
            recoveredAmount,
            address(strategy),
            amount
        );
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
        emit Recovered(tokenAddress, tokenAmount, address(strategy), 0);
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
        emit Recovered(address(0), amount, address(strategy), 0);
    }
}
