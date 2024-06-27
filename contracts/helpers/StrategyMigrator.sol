// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../lib/Ownable.sol";
import "../lib/SafeERC20.sol";
import "./../interfaces/ISimpleRouter.sol";
import "./../interfaces/IYakStrategy.sol";
import "./../interfaces/IWGAS.sol";

contract StrategyMigrator is Ownable {
    using SafeERC20 for IERC20;

    address immutable WGAS;

    event Recovered(address token, uint256 amount);

    constructor(address _wgas) {
        WGAS = _wgas;
    }

    function migrate(address _fromStrategy, address _toStrategy, uint256 _fromShares, uint256 _minAmountOut) external {
        address depositToken = IYakStrategy(_fromStrategy).depositToken();
        address depositTokenTo = IYakStrategy(_toStrategy).depositToken();
        bool migrateFromNative = depositToken == address(0);
        require(
            (migrateFromNative && depositTokenTo == WGAS) || depositToken == depositTokenTo,
            "StrategyMigrator::Migration impossible"
        );
        // Transfer shares
        require(
            IERC20(_fromStrategy).transferFrom(msg.sender, address(this), _fromShares),
            "StrategyMigrator::transferFrom failed"
        );

        // Withdraw
        uint256 balanceBefore =
            migrateFromNative ? address(this).balance : IERC20(depositToken).balanceOf(address(this));
        IYakStrategy(_fromStrategy).withdraw(_fromShares);
        uint256 balanceAfter = migrateFromNative ? address(this).balance : IERC20(depositToken).balanceOf(address(this));
        uint256 amountOut = balanceAfter - balanceBefore;
        require(amountOut >= _minAmountOut, "StrategyMigrator::amountOut too low");

        // Deposit
        if (migrateFromNative) {
            IWGAS(WGAS).deposit{value: amountOut}();
        }
        IERC20(depositTokenTo).approve(_toStrategy, amountOut);
        IYakStrategy(_toStrategy).depositFor(msg.sender, amountOut);
    }

    receive() external payable {}

    /**
     * @notice Recover ERC20 from contract
     * @param tokenAddress token address
     * @param tokenAmount amount to recover
     */
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        require(tokenAmount > 0);
        IERC20(tokenAddress).safeTransfer(msg.sender, tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    /**
     * @notice Recover GAS from contract
     * @param amount amount
     */
    function recoverGas(uint256 amount) external onlyOwner {
        require(amount > 0);
        payable(msg.sender).transfer(amount);
        emit Recovered(address(0), amount);
    }
}
