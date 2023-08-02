// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../../../YakStrategyV2.sol";
import "../../../lib/SafeERC20.sol";
import "../../../interfaces/IWGAS.sol";

import "./interfaces/IBlpProxy.sol";
import "./interfaces/IGmxRewardRouter.sol";

contract CompoundingBlp is YakStrategyV2 {
    using SafeERC20 for IERC20;

    IWGAS private constant WAVAX = IWGAS(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);

    IBlpProxy public proxy;

    constructor(
        string memory _name,
        address _gmxProxy,
        address _timelock,
        StrategySettings memory _strategySettings
    ) YakStrategyV2(_strategySettings) {
        name = _name;
        proxy = IBlpProxy(_gmxProxy);
        devAddr = 0x2D580F9CF2fB2D09BC411532988F2aFdA4E7BefF;

        updateDepositsEnabled(true);
        transferOwnership(_timelock);
        emit Reinvest(0, 0);
    }

    function setProxy(address _proxy) external onlyOwner {
        proxy = IBlpProxy(_proxy);
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
    function depositWithPermit(
        uint256,
        uint256,
        uint8,
        bytes32,
        bytes32
    ) external pure override {
        revert();
    }

    function depositFor(address account, uint256 amount) external override {
        _deposit(account, amount);
    }

    function _deposit(address account, uint256 amount) internal {
        require(amount > 0, "CompoundingBLP::_deposit amount");
        require(DEPOSITS_ENABLED == true, "CompoundingBLP::_deposit disabled");
        if (MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST > 0) {
            uint256 reward = checkReward();
            if (reward > MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST) {
                _reinvest(reward);
            }
        }
        _mint(account, getSharesForDepositTokens(amount));
        require(depositToken.transferFrom(msg.sender, _depositor(), amount), "CompoundingBLP::transfer failed");
        emit Deposit(account, amount);
    }

    function withdraw(uint256 amount) external override {
        uint256 depositTokenAmount = getDepositTokensForShares(amount);
        require(depositTokenAmount > 0, "CompoundingBLP::withdraw");
        _withdrawDepositTokens(depositTokenAmount);
        depositToken.safeTransfer(msg.sender, depositTokenAmount);
        _burn(msg.sender, amount);
        emit Withdraw(msg.sender, depositTokenAmount);
    }

    function _withdrawDepositTokens(uint256 _amount) private {
        proxy.withdrawGlp(_amount);
    }

    function reinvest() external override onlyEOA {
        uint256 amount = checkReward();
        require(amount >= MIN_TOKENS_TO_REINVEST, "CompoundingBLP::reinvest");
        _reinvest(amount);
    }

    /**
     * @notice Reinvest rewards from staking contract to deposit tokens
     * @dev Reverts if the expected amount of tokens are not returned from `MasterChef`
     */
    function _reinvest(uint256 _amount) private {
        proxy.claimReward();

        uint256 devFee = (_amount * DEV_FEE_BIPS) / BIPS_DIVISOR;
        if (devFee > 0) {
            rewardToken.safeTransfer(devAddr, devFee);
        }

        uint256 reinvestFee = (_amount * REINVEST_REWARD_BIPS) / BIPS_DIVISOR;
        if (reinvestFee > 0) {
            rewardToken.safeTransfer(msg.sender, reinvestFee);
        }

        _amount = _amount - devFee - reinvestFee;
        rewardToken.safeTransfer(_depositor(), _amount);
        proxy.buyAndStakeGlp(_amount);

        emit Reinvest(totalDeposits(), totalSupply);
    }

    function checkReward() public view override returns (uint256) {
        uint256 pendingReward = proxy.pendingRewards();
        uint256 rewardTokenBalance = rewardToken.balanceOf(address(this));
        return rewardTokenBalance + pendingReward;
    }

    /**
     * @notice Estimate recoverable balance after withdraw fee
     * @return deposit tokens after withdraw fee
     */
    function estimateDeployedBalance() external view override returns (uint256) {
        uint256 depositBalance = totalDeposits();
        return depositBalance;
    }

    function totalDeposits() public view override returns (uint256) {
        return proxy.totalDeposits();
    }

    function rescueDeployedFunds(
        uint256, /*minReturnAmountAccepted*/
        bool disableDeposits
    ) external override onlyOwner {
        uint256 balance = totalDeposits();
        proxy.emergencyWithdraw(balance);
        emit Reinvest(totalDeposits(), totalSupply);
        if (DEPOSITS_ENABLED == true && disableDeposits == true) {
            updateDepositsEnabled(false);
        }
    }

    function _depositor() private view returns (address) {
        return address(proxy.gmxDepositor());
    }
}
