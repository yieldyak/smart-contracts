// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../lib/SafeERC20.sol";
import "./../interfaces/ISimpleRouter.sol";
import "./../interfaces/IYakStrategy.sol";

contract ZapForSimpleRouter {
    using SafeERC20 for IERC20;

    address public simpleRouter;
    address public devAddr;

    event UpdateRouter(address oldRouter, address newRouter);

    /**
     * @notice Only called by dev
     */
    modifier onlyDev() {
        require(msg.sender == devAddr, "ZapForSimpleRouter::onlyDev");
        _;
    }

    constructor(
        address _simpleRouter
    ) {
        devAddr = msg.sender;
        simpleRouter = _simpleRouter;
    }

    function zapIn(address _strategy, address _tokenIn, uint256 _amountIn) external {
        // Swap
        address depositToken = IYakStrategy(_strategy).depositToken();
        IERC20(_tokenIn).approve(simpleRouter, _amountIn);
        FormattedOffer memory trade = ISimpleRouter(simpleRouter).query(_amountIn, _tokenIn, depositToken);
        uint256 amountOut = ISimpleRouter(simpleRouter).swap(trade);
        require(amountOut > 0, "ZapForSimpleRouter::amountOut too low");

        // Deposit
        IERC20(depositToken).approve(_strategy, amountOut);
        IYakStrategy(_strategy).depositFor(msg.sender, amountOut);
    }

    function zapOut(address _strategy, address _tokenOut, uint256 _sharesOut) external {
        // Transfer shares
        require(IERC20(_strategy).transferFrom(msg.sender, address(this), _sharesOut), "ZapForSimpleRouter::transferFrom failed");

        // Withdraw
        address depositToken = IYakStrategy(_strategy).depositToken();
        uint256 balanceBefore = IERC20(depositToken).balanceOf(address(this));
        IYakStrategy(_strategy).withdraw(_sharesOut);
        uint256 balanceAfter = IERC20(depositToken).balanceOf(address(this));
        uint256 amountIn = balanceAfter - balanceBefore;
        require(amountIn > 0, "ZapForSimpleRouter::amountIn too low");

        // Swap
        IERC20(depositToken).approve(simpleRouter, amountIn);
        FormattedOffer memory trade = ISimpleRouter(simpleRouter).query(amountIn, depositToken, _tokenOut);
        uint256 amountOut = ISimpleRouter(simpleRouter).swap(trade);
        require(amountOut > 0, "ZapForSimpleRouter::amountOut too low");

        // Transfer
        require(IERC20(_tokenOut).transfer(msg.sender, amountOut), "ZapForSimpleRouter::transfer failed");

    }
    

    function updateRouter(address _simpleRouter) external onlyDev {
        emit UpdateRouter(simpleRouter, _simpleRouter);
        simpleRouter = _simpleRouter;
    }

}