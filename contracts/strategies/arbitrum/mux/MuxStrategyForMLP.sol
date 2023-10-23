// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../../../YakStrategyV3.sol";
import "../../../lib/SafeERC20.sol";

import "./interfaces/IMuxProxy.sol";

contract MuxStrategyForMLP is YakStrategyV3 {
    using SafeERC20 for IERC20;

    IMuxProxy public proxy;

    constructor(address _muxProxy, StrategySettings memory _strategySettings) YakStrategyV3(_strategySettings) {
        proxy = IMuxProxy(_muxProxy);

        emit Reinvest(0, 0);
    }

    function setProxy(address _proxy) external onlyOwner {
        proxy = IMuxProxy(_proxy);
    }

    /**
     * @notice Deposit tokens to receive receipt tokens
     * @param amount Amount of tokens to deposit
     */
    function deposit(uint256 amount) external override {
        _deposit(msg.sender, amount);
    }

    /**
     * @dev Permit not supported by fsGLP
     */
    function depositWithPermit(uint256, uint256, uint8, bytes32, bytes32) external pure override {
        revert();
    }

    function depositFor(address account, uint256 amount) external override {
        _deposit(account, amount);
    }

    function _deposit(address account, uint256 amount) internal {
        require(DEPOSITS_ENABLED == true && !proxy.largePendingOrder(), "MuxStrategyForMLP::_deposit");
        _reinvest(true);
        require(depositToken.transferFrom(msg.sender, address(this), amount), "MuxStrategyForMLP::transfer failed");
        _mint(account, getSharesForDepositTokens(amount));
        require(amount > 0, "MuxStrategyForMLP::_stakeDepositTokens");
        depositToken.safeTransfer(address(proxy.muxDepositor()), amount);
        proxy.stakeMlp(depositToken.balanceOf(address(proxy.muxDepositor())));
        emit Deposit(account, amount);
    }

    function withdraw(uint256 amount) external override {
        uint256 depositTokenAmount = getDepositTokensForShares(amount);
        require(depositTokenAmount > 0, "MuxStrategyForMLP::withdraw");
        _withdrawDepositTokens(depositTokenAmount);
        depositToken.safeTransfer(msg.sender, depositTokenAmount);
        _burn(msg.sender, amount);
        emit Withdraw(msg.sender, depositTokenAmount);
    }

    function _withdrawDepositTokens(uint256 _amount) private {
        proxy.withdrawMlp(_amount);
    }

    function reinvest() external override onlyEOA {
        uint256 amount = checkReward();
        require(amount >= MIN_TOKENS_TO_REINVEST, "MuxStrategyForMLP::reinvest");
        _reinvest(false);
    }

    /**
     * @notice Reinvest rewards from staking contract to deposit tokens
     * @dev Reverts if the expected amount of tokens are not returned from `MasterChef`
     */
    function _reinvest(bool _userDeposit) private {
        proxy.claimReward();
        uint256 amount = rewardToken.balanceOf(address(this));
        if (amount > MIN_TOKENS_TO_REINVEST) {
            uint256 devFee = (amount * DEV_FEE_BIPS) / BIPS_DIVISOR;
            if (devFee > 0) {
                rewardToken.safeTransfer(feeCollector, devFee);
            }

            uint256 reinvestFee = _userDeposit ? 0 : (amount * REINVEST_REWARD_BIPS) / BIPS_DIVISOR;
            if (reinvestFee > 0) {
                rewardToken.safeTransfer(msg.sender, reinvestFee);
            }

            rewardToken.safeTransfer(address(proxy), amount - devFee - reinvestFee);
            proxy.orderMlp(amount - devFee - reinvestFee);

            if (!_userDeposit) {
                uint256 unstakedMlp = depositToken.balanceOf(address(proxy.muxDepositor()));
                if (unstakedMlp > 0) {
                    proxy.stakeMlp(unstakedMlp);
                }
            }

            emit Reinvest(totalDeposits(), totalSupply);
        }
    }

    function checkReward() public view override returns (uint256) {
        return rewardToken.balanceOf(address(this)) + proxy.pendingRewards();
    }

    function totalDeposits() public view override returns (uint256) {
        return proxy.totalDeposits();
    }

    function rescueDeployedFunds(uint256) external view override onlyOwner {
        revert("Unsupported");
    }
}
