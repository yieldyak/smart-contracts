// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../YakStrategyV2.sol";
import "../interfaces/IWAVAX.sol";
import "../lib/SafeERC20.sol";
import "./../interfaces/ISimpleRouter.sol";

/**
 * @notice BaseStrategy
 */
abstract contract BaseStrategy is YakStrategyV2 {
    using SafeERC20 for IERC20;

    IWAVAX internal immutable WAVAX;

    struct BaseStrategySettings {
        string name;
        address platformToken;
        address owner;
        address dev;
        address feeCollector;
        address[] rewards;
        address simpleRouter;
    }

    struct Reward {
        address reward;
        uint256 amount;
    }

    address feeCollector;

    address[] public supportedRewards;
    uint256 public rewardCount;
    ISimpleRouter public simpleRouter;

    event AddReward(address rewardToken);
    event RemoveReward(address rewardToken);
    event UpdateRouter(address oldRouter, address newRouter);
    event UpdateFeeCollector(address oldFeeCollector, address newFeeCollector);

    constructor(BaseStrategySettings memory _settings, StrategySettings memory _strategySettings)
        YakStrategyV2(_strategySettings)
    {
        name = _settings.name;
        WAVAX = IWAVAX(_settings.platformToken);
        devAddr = _settings.dev;
        feeCollector = _settings.feeCollector;

        supportedRewards = _settings.rewards;
        rewardCount = _settings.rewards.length;

        simpleRouter = ISimpleRouter(_settings.simpleRouter);
        require(_strategySettings.minTokensToReinvest > 0, "BaseStrategy::Invalid configuration");

        updateDepositsEnabled(true);
        transferOwnership(_settings.owner);
        emit Reinvest(0, 0);
    }

    function updateRouter(address _router) public onlyDev {
        address oldRouter = address(simpleRouter);
        simpleRouter = ISimpleRouter(_router);
        emit UpdateRouter(oldRouter, _router);
    }

    function updateFeeCollector(address _feeCollector) public onlyDev {
        address oldFeeCollector = address(feeCollector);
        feeCollector = _feeCollector;
        emit UpdateFeeCollector(oldFeeCollector, _feeCollector);
    }

    function addReward(address _rewardToken) public onlyDev {
        bool found;
        for (uint256 i = 0; i < supportedRewards.length; i++) {
            if (_rewardToken == supportedRewards[i]) {
                found = true;
            }
        }
        if (!found) {
            rewardCount++;
            supportedRewards.push(_rewardToken);
            emit AddReward(_rewardToken);
        }
    }

    function removeReward(address _rewardToken) public onlyDev {
        bool found;
        for (uint256 i = 0; i < supportedRewards.length; i++) {
            if (_rewardToken == supportedRewards[i]) {
                found = true;
                supportedRewards[i] = supportedRewards[supportedRewards.length - 1];
            }
        }
        require(found, "BaseStrategy::Reward to delete not found!");
        supportedRewards.pop();
        rewardCount--;
        emit RemoveReward(_rewardToken);
    }

    function calculateDepositFee(uint256 _amount) public view returns (uint256) {
        return _calculateDepositFee(_amount);
    }

    function calculateWithdrawFee(uint256 _amount) public view returns (uint256) {
        return _calculateWithdrawFee(_amount);
    }

    /**
     * @notice Deposit tokens to receive receipt tokens
     * @param _amount Amount of tokens to deposit
     */
    function deposit(uint256 _amount) external override {
        _deposit(msg.sender, _amount);
    }

    /**
     * @notice Deposit using Permit
     * @param _amount Amount of tokens to deposit
     * @param _deadline The time at which to expire the signature
     * @param _v The recovery byte of the signature
     * @param _r Half of the ECDSA signature pair
     * @param _s Half of the ECDSA signature pair
     */
    function depositWithPermit(uint256 _amount, uint256 _deadline, uint8 _v, bytes32 _r, bytes32 _s)
        external
        override
    {
        depositToken.permit(msg.sender, address(this), _amount, _deadline, _v, _r, _s);
        _deposit(msg.sender, _amount);
    }

    function depositFor(address _account, uint256 _amount) external override {
        _deposit(_account, _amount);
    }

    function _deposit(address _account, uint256 _amount) internal {
        require(DEPOSITS_ENABLED == true, "BaseStrategy::Deposits disabled");
        _reinvest(true);
        require(
            depositToken.transferFrom(msg.sender, address(this), _amount), "BaseStrategy::Deposit token transfer failed"
        );
        uint256 depositFee = _calculateDepositFee(_amount);
        _mint(_account, getSharesForDepositTokens(_amount - depositFee));
        _stakeDepositTokens(_amount, depositFee);
        emit Deposit(_account, _amount);
    }

    /**
     * @notice Deposit fee bips from underlying farm
     */
    function _getDepositFeeBips() internal view virtual returns (uint256) {
        return 0;
    }

    /**
     * @notice Calculate deposit fee of underlying farm
     * @dev Override if deposit fee is calculated dynamically
     */
    function _calculateDepositFee(uint256 _amount) internal view virtual returns (uint256) {
        uint256 depositFeeBips = _getDepositFeeBips();
        return (_amount * depositFeeBips) / _bip();
    }

    function withdraw(uint256 _amount) external override {
        uint256 depositTokenAmount = getDepositTokensForShares(_amount);
        require(depositTokenAmount > 0, "BaseStrategy::Withdraw amount too low");
        uint256 withdrawAmount = _withdrawFromStakingContract(depositTokenAmount);
        uint256 withdrawFee = _calculateWithdrawFee(depositTokenAmount);
        depositToken.safeTransfer(msg.sender, withdrawAmount - withdrawFee);
        _burn(msg.sender, _amount);
        emit Withdraw(msg.sender, depositTokenAmount);
    }

    /**
     * @notice Withdraw fee bips from underlying farm
     * @dev Important: Do not override if withdraw fee is deducted from the amount returned by _withdrawFromStakingContract
     */
    function _getWithdrawFeeBips() internal view virtual returns (uint256) {
        return 0;
    }

    /**
     * @notice Calculate withdraw fee of underlying farm
     * @dev Override if withdraw fee is calculated dynamically
     * @dev Important: Do not override if withdraw fee is deducted from the amount returned by _withdrawFromStakingContract
     */
    function _calculateWithdrawFee(uint256 _amount) internal view virtual returns (uint256) {
        uint256 withdrawFeeBips = _getWithdrawFeeBips();
        return (_amount * withdrawFeeBips) / _bip();
    }

    function reinvest() external override onlyEOA {
        _reinvest(false);
    }

    function _convertPoolRewardsToRewardToken() private returns (uint256) {
        uint256 rewardTokenAmount = rewardToken.balanceOf(address(this));
        uint256 count = supportedRewards.length;
        for (uint256 i = 0; i < count; i++) {
            address reward = supportedRewards[i];
            if (reward == address(WAVAX)) {
                uint256 balance = address(this).balance;
                if (balance > 0) {
                    WAVAX.deposit{value: balance}();
                }
                if (address(rewardToken) == address(WAVAX)) {
                    rewardTokenAmount += balance;
                    continue;
                }
            }
            uint256 amount = IERC20(reward).balanceOf(address(this));
            if (amount > 0) {
                FormattedOffer memory offer = simpleRouter.query(amount, reward, address(rewardToken));
                rewardTokenAmount += _swap(offer);
            }
        }
        return rewardTokenAmount;
    }

    /**
     * @notice Reinvest rewards from staking contract to deposit tokens
     * @dev Reverts if the expected amount of tokens are not returned from the staking contract
     * @param userDeposit Controls whether or not a gas refund is payed to msg.sender
     */
    function _reinvest(bool userDeposit) private {
        _getRewards();
        uint256 amount = _convertPoolRewardsToRewardToken();
        if (amount > MIN_TOKENS_TO_REINVEST) {
            uint256 devFee = (amount * DEV_FEE_BIPS) / BIPS_DIVISOR;
            if (devFee > 0) {
                rewardToken.safeTransfer(feeCollector, devFee);
            }

            uint256 reinvestFee = userDeposit ? 0 : (amount * REINVEST_REWARD_BIPS) / BIPS_DIVISOR;
            if (reinvestFee > 0) {
                rewardToken.safeTransfer(msg.sender, reinvestFee);
            }

            uint256 depositTokenAmount = _convertRewardTokenToDepositToken(amount - devFee - reinvestFee);

            if (depositTokenAmount > 0) {
                uint256 depositFee = _calculateDepositFee(depositTokenAmount);
                _stakeDepositTokens(depositTokenAmount, depositFee);
                emit Reinvest(totalDeposits(), totalSupply);
            }
        }
    }

    function _convertRewardTokenToDepositToken(uint256 _fromAmount) internal virtual returns (uint256 toAmount) {
        if (address(rewardToken) == address(depositToken)) return _fromAmount;
        FormattedOffer memory offer = simpleRouter.query(_fromAmount, address(rewardToken), address(depositToken));
        return _swap(offer);
    }

    function _stakeDepositTokens(uint256 _amount, uint256 _depositFee) private {
        require(_amount > 0, "BaseStrategy::Stake amount too low");
        _depositToStakingContract(_amount, _depositFee);
    }

    function _swap(FormattedOffer memory _offer) internal returns (uint256 amountOut) {
        if (_offer.amounts.length > 0 && _offer.amounts[_offer.amounts.length - 1] > 0) {
            IERC20(_offer.path[0]).approve(address(simpleRouter), _offer.amounts[0]);
            return simpleRouter.swap(_offer);
        }
        return 0;
    }

    function checkReward() public view override returns (uint256) {
        Reward[] memory rewards = _pendingRewards();
        uint256 estimatedTotalReward = rewardToken.balanceOf(address(this));
        for (uint256 i = 0; i < rewards.length; i++) {
            address reward = rewards[i].reward;
            if (reward == address(WAVAX)) {
                rewards[i].amount += address(this).balance;
            }
            if (reward == address(rewardToken)) {
                estimatedTotalReward += rewards[i].amount;
            } else if (reward > address(0)) {
                uint256 balance = IERC20(reward).balanceOf(address(this));
                uint256 amount = balance + rewards[i].amount;
                if (amount > 0) {
                    FormattedOffer memory offer = simpleRouter.query(amount, reward, address(rewardToken));
                    estimatedTotalReward += offer.amounts.length > 1 ? offer.amounts[offer.amounts.length - 1] : 0;
                }
            }
        }
        return estimatedTotalReward;
    }

    /**
     * @notice Estimate recoverable balance after withdraw fee
     * @return deposit tokens after withdraw fee
     */
    function estimateDeployedBalance() external view override returns (uint256) {
        uint256 depositBalance = totalDeposits();
        uint256 withdrawFee = _calculateWithdrawFee(depositBalance);
        return depositBalance - withdrawFee;
    }

    function rescueDeployedFunds(uint256 _minReturnAmountAccepted, bool /*_disableDeposits*/ )
        external
        override
        onlyOwner
    {
        uint256 balanceBefore = depositToken.balanceOf(address(this));
        _emergencyWithdraw();
        uint256 balanceAfter = depositToken.balanceOf(address(this));
        require(
            balanceAfter - balanceBefore >= _minReturnAmountAccepted,
            "BaseStrategy::Emergency withdraw minimum return amount not reached"
        );
        emit Reinvest(totalDeposits(), totalSupply);
        if (DEPOSITS_ENABLED == true) {
            updateDepositsEnabled(false);
        }
    }

    function _bip() internal view virtual returns (uint256) {
        return 10000;
    }

    /* ABSTRACT */
    function _depositToStakingContract(uint256 _amount, uint256 _depositFee) internal virtual;

    function _withdrawFromStakingContract(uint256 _amount) internal virtual returns (uint256 withdrawAmount);

    function _emergencyWithdraw() internal virtual;

    function _getRewards() internal virtual;

    function _pendingRewards() internal view virtual returns (Reward[] memory);
}
