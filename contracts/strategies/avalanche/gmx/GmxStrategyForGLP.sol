// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../../../YakStrategyV2.sol";
import "../../../lib/SafeERC20.sol";
import "./../../../lib/SafeMath.sol";
import "../../../interfaces/IWAVAX.sol";

import "./interfaces/IGmxProxy.sol";
import "./interfaces/IGmxRewardRouter.sol";

/**
 * @notice Adapter strategy for MasterChef.
 */
contract GmxStrategyForGLP is YakStrategyV2 {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IWAVAX private constant WAVAX = IWAVAX(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);

    IGmxProxy public proxy;

    constructor(
        string memory _name,
        address _depositToken,
        address _gmxProxy,
        address _timelock,
        StrategySettings memory _strategySettings
    ) YakStrategyV2(_strategySettings) {
        name = _name;
        depositToken = IERC20(_depositToken);
        rewardToken = IERC20(address(WAVAX));
        proxy = IGmxProxy(_gmxProxy);
        devAddr = 0x2D580F9CF2fB2D09BC411532988F2aFdA4E7BefF;

        updateDepositsEnabled(true);
        transferOwnership(_timelock);
        emit Reinvest(0, 0);
    }

    function setProxy(address _proxy) external onlyOwner {
        proxy = IGmxProxy(_proxy);
    }

    /**
     * @notice Deposit tokens to receive receipt tokens
     * @param amount Amount of tokens to deposit
     */
    function deposit(uint256 amount) external override {
        _deposit(msg.sender, amount);
    }

    /**
     * @notice Deposit using Permit
     * @param amount Amount of tokens to deposit
     * @param deadline The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function depositWithPermit(
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {
        depositToken.permit(msg.sender, address(this), amount, deadline, v, r, s);
        _deposit(msg.sender, amount);
    }

    function depositFor(address account, uint256 amount) external override {
        _deposit(account, amount);
    }

    function _deposit(address account, uint256 amount) internal {
        require(DEPOSITS_ENABLED == true, "GmxStrategyForGLP::_deposit");
        if (MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST > 0) {
            uint256 reward = checkReward();
            if (reward > MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST) {
                _reinvest(reward);
            }
        }
        require(depositToken.transferFrom(msg.sender, address(this), amount), "GmxStrategyForGLP::transfer failed");
        _mint(account, getSharesForDepositTokens(amount));
        _stakeDepositTokens(amount);
        emit Deposit(account, amount);
    }

    function withdraw(uint256 amount) external override {
        uint256 depositTokenAmount = getDepositTokensForShares(amount);
        require(depositTokenAmount > 0, "GmxStrategyForGLP::withdraw");
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
        require(amount >= MIN_TOKENS_TO_REINVEST, "GmxStrategyForGLP::reinvest");
        _reinvest(amount);
    }

    /**
     * @notice Reinvest rewards from staking contract to deposit tokens
     * @dev Reverts if the expected amount of tokens are not returned from `MasterChef`
     */
    function _reinvest(uint256 _amount) private {
        proxy.claimReward(_rewardTracker());

        uint256 devFee = _amount.mul(DEV_FEE_BIPS).div(BIPS_DIVISOR);
        if (devFee > 0) {
            rewardToken.safeTransfer(devAddr, devFee);
        }

        uint256 reinvestFee = _amount.mul(REINVEST_REWARD_BIPS).div(BIPS_DIVISOR);
        if (reinvestFee > 0) {
            rewardToken.safeTransfer(msg.sender, reinvestFee);
        }

        rewardToken.safeTransfer(address(proxy), _amount.sub(devFee).sub(reinvestFee));
        proxy.buyAndStakeGlp(_amount.sub(devFee).sub(reinvestFee));

        emit Reinvest(totalDeposits(), totalSupply);
    }

    function _stakeDepositTokens(uint256 _amount) private {
        require(_amount > 0, "GmxStrategyForGLP::_stakeDepositTokens");
        depositToken.safeTransfer(_depositor(), _amount);
    }

    function checkReward() public view override returns (uint256) {
        uint256 pendingReward = proxy.pendingRewards(_rewardTracker());
        uint256 rewardTokenBalance = rewardToken.balanceOf(address(this));
        return rewardTokenBalance.add(pendingReward);
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
        return proxy.totalDeposits(_rewardTracker());
    }

    function rescueDeployedFunds(
        uint256, /*minReturnAmountAccepted*/
        bool disableDeposits
    ) external override onlyOwner {
        uint256 balance = totalDeposits();
        proxy.emergencyWithdrawGLP(balance);
        emit Reinvest(totalDeposits(), totalSupply);
        if (DEPOSITS_ENABLED == true && disableDeposits == true) {
            updateDepositsEnabled(false);
        }
    }

    function _depositor() private view returns (address) {
        return address(proxy.gmxDepositor());
    }

    function _rewardTracker() private view returns (address) {
        address gmxRewardRouter = proxy.gmxRewardRouter();
        return IGmxRewardRouter(gmxRewardRouter).feeGlpTracker();
    }
}
