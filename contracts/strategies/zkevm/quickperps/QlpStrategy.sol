// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../../YakStrategyV2.sol";
import "../../../lib/DexLibrary.sol";
import "../../../lib/SafeERC20.sol";

import "./interfaces/IRewardRouter.sol";
import "./interfaces/IRewardTracker.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IQlpManager.sol";

contract QlpStrategy is YakStrategyV2 {
    using SafeERC20 for IERC20;

    address internal constant WETH = 0x4F9A0e7FD2Bf6067db6994CF12E4495Df938E6e9;
    uint256 internal constant USDQ_PRICE_PRECISION = 1e30;

    struct QlpStrategySettings {
        string name;
        address platformToken;
        address rewardRouter;
        uint256 depositFeeBips;
        uint256 withdrawFeeBips;
        RewardSwapPair[] rewardSwapPairs;
        address dev;
        address owner;
    }

    struct Reward {
        address reward;
        uint256 amount;
    }

    struct RewardSwapPair {
        address reward;
        address swapPair;
        uint256 swapFee;
    }

    IRewardRouter immutable rewardRouter;
    IRewardTracker immutable feeQlpTracker;
    IVault immutable vault;
    address immutable qlpManager;
    address immutable usdg;

    // reward -> swapPair
    mapping(address => RewardSwapPair) public rewardSwapPairs;
    address[] public supportedRewards;
    uint256 public rewardCount;
    uint256 depositFeeBips;
    uint256 withdrawFeeBips;
    address alternativeTokenIn;
    address pairAlternativeTokenIn;
    uint256 swapFeeAlternativePair;

    event AddReward(address rewardToken, address swapPair);
    event RemoveReward(address rewardToken);
    event UpdateDepositFee(uint256 oldValue, uint256 newValue);
    event UpdateWithdrawFee(uint256 oldValue, uint256 newValue);

    constructor(QlpStrategySettings memory _settings, StrategySettings memory _strategySettings)
        YakStrategyV2(_strategySettings)
    {
        name = _settings.name;

        for (uint256 i = 0; i < _settings.rewardSwapPairs.length; i++) {
            _addReward(
                _settings.rewardSwapPairs[i].reward,
                _settings.rewardSwapPairs[i].swapPair,
                _settings.rewardSwapPairs[i].swapFee
            );
        }

        rewardRouter = IRewardRouter(_settings.rewardRouter);
        feeQlpTracker = IRewardTracker(rewardRouter.feeQlpTracker());
        qlpManager = rewardRouter.qlpManager();
        vault = IVault(IQlpManager(qlpManager).vault());
        usdg = vault.usdq();

        depositFeeBips = _settings.depositFeeBips;
        withdrawFeeBips = _settings.withdrawFeeBips;

        updateDepositsEnabled(true);
        devAddr = _settings.dev;
        transferOwnership(_settings.owner);
        emit Reinvest(0, 0);
    }

    function addReward(address _rewardToken, address _swapPair) external onlyDev {
        _addReward(_rewardToken, _swapPair, DexLibrary.DEFAULT_SWAP_FEE);
    }

    function addReward(address _rewardToken, address _swapPair, uint256 _swapFee) external onlyDev {
        _addReward(_rewardToken, _swapPair, _swapFee);
    }

    function _addReward(address _rewardToken, address _swapPair, uint256 _swapFee) internal {
        if (_rewardToken != address(rewardToken)) {
            require(
                DexLibrary.checkSwapPairCompatibility(IPair(_swapPair), _rewardToken, address(rewardToken)),
                "VariableRewardsStrategy::Swap pair does not contain reward token"
            );
        }
        rewardSwapPairs[_rewardToken] = RewardSwapPair({reward: _rewardToken, swapPair: _swapPair, swapFee: _swapFee});
        supportedRewards.push(_rewardToken);
        rewardCount = rewardCount + 1;
        emit AddReward(_rewardToken, _swapPair);
    }

    function removeReward(address _rewardToken) external onlyDev {
        delete rewardSwapPairs[_rewardToken];
        bool found = false;
        for (uint256 i = 0; i < supportedRewards.length; i++) {
            if (_rewardToken == supportedRewards[i]) {
                found = true;
                supportedRewards[i] = supportedRewards[supportedRewards.length - 1];
            }
        }
        require(found, "VariableRewardsStrategy::Reward to delete not found!");
        supportedRewards.pop();
        rewardCount = rewardCount - 1;
        emit RemoveReward(_rewardToken);
    }

    function updateDepositFee(uint256 _depositFeeBips) external onlyDev {
        require(_depositFeeBips < BIPS_DIVISOR, "QlpStrategy::Fee too high");
        emit UpdateDepositFee(depositFeeBips, _depositFeeBips);
        depositFeeBips = _depositFeeBips;
    }

    function updateWithdrawFee(uint256 _withdrawFeeBips) external onlyDev {
        require(_withdrawFeeBips < BIPS_DIVISOR, "QlpStrategy::Fee too high");
        emit UpdateWithdrawFee(withdrawFeeBips, _withdrawFeeBips);
        withdrawFeeBips = _withdrawFeeBips;
    }

    function updateQlpTokenIn(address _pair, uint256 _swapFee) external onlyDev {
        address token0 = IPair(_pair).token0();
        address token1 = IPair(_pair).token1();
        require(token0 == WETH || token1 == WETH, "QlpStrategy::Invalid pair");
        alternativeTokenIn = token0 == WETH ? token0 : token1;
        pairAlternativeTokenIn = _pair;
        swapFeeAlternativePair = _swapFee;
    }

    function calculateDepositFee(uint256 _amount) public view returns (uint256) {
        return (_amount * depositFeeBips) / BIPS_DIVISOR;
    }

    function calculateWithdrawFee(uint256 _amount) public view returns (uint256) {
        return (_amount * withdrawFeeBips) / BIPS_DIVISOR;
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
        require(DEPOSITS_ENABLED == true, "VariableRewardsStrategy::Deposits disabled");
        uint256 maxPendingRewards = MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST;
        if (maxPendingRewards > 0) {
            uint256 estimatedTotalReward = checkReward();
            if (estimatedTotalReward > maxPendingRewards) {
                _reinvest(true);
            }
        }
        uint256 depositFee = calculateDepositFee(_amount);
        _mint(_account, getSharesForDepositTokens(_amount - depositFee));
        depositToken.safeTransferFrom(msg.sender, address(this), _amount);
        emit Deposit(_account, _amount);
    }

    function withdraw(uint256 _amount) external override {
        uint256 depositTokenAmount = getDepositTokensForShares(_amount);
        require(depositTokenAmount > 0, "VariableRewardsStrategy::Withdraw amount too low");
        uint256 withdrawFee = calculateWithdrawFee(depositTokenAmount);
        depositToken.safeTransfer(msg.sender, depositTokenAmount - withdrawFee);
        _burn(msg.sender, _amount);
        emit Withdraw(msg.sender, depositTokenAmount);
    }

    function _convertPoolRewardsToRewardToken() private returns (uint256) {
        uint256 rewardTokenAmount = rewardToken.balanceOf(address(this));
        uint256 count = supportedRewards.length;
        for (uint256 i = 0; i < count; i++) {
            address reward = supportedRewards[i];
            if (reward == WETH) {
                if (address(rewardToken) == WETH) {
                    continue;
                }
            }
            uint256 amount = IERC20(reward).balanceOf(address(this));
            if (amount > 0) {
                address swapPair = rewardSwapPairs[reward].swapPair;
                if (swapPair > address(0)) {
                    rewardTokenAmount += DexLibrary.swap(
                        amount, reward, address(rewardToken), IPair(swapPair), rewardSwapPairs[reward].swapFee
                    );
                }
            }
        }
        return rewardTokenAmount;
    }

    function reinvest() external override onlyEOA {
        _reinvest(false);
    }

    /**
     * @notice Reinvest rewards from staking contract to deposit tokens
     * @dev Reverts if the expected amount of tokens are not returned from the staking contract
     */
    function _reinvest(bool userDeposit) private {
        rewardRouter.handleRewards(true, false, false);
        uint256 amount = _convertPoolRewardsToRewardToken();
        if (!userDeposit) {
            require(amount >= MIN_TOKENS_TO_REINVEST, "VariableRewardsStrategy::Reinvest amount too low");
        }

        uint256 devFee = (amount * DEV_FEE_BIPS) / BIPS_DIVISOR;
        if (devFee > 0) {
            rewardToken.safeTransfer(devAddr, devFee);
        }

        uint256 reinvestFee = (amount * REINVEST_REWARD_BIPS) / BIPS_DIVISOR;
        if (reinvestFee > 0) {
            rewardToken.safeTransfer(msg.sender, reinvestFee);
        }

        amount = amount - devFee - reinvestFee;
        address tokenIn = WETH;
        if (!vaultHasEthCapacity(amount)) {
            tokenIn = alternativeTokenIn;
            amount = DexLibrary.swap(amount, WETH, tokenIn, IPair(pairAlternativeTokenIn), swapFeeAlternativePair);
        }
        IERC20(tokenIn).approve(qlpManager, amount);
        rewardRouter.mintAndStakeQlp(tokenIn, amount, 0, 0);

        emit Reinvest(totalDeposits(), totalSupply);
    }

    function vaultHasEthCapacity(uint256 _amountIn) internal view returns (bool) {
        uint256 price = vault.getMinPrice(WETH);
        uint256 usdgAmount = (_amountIn * price) / USDQ_PRICE_PRECISION;
        usdgAmount = vault.adjustForDecimals(usdgAmount, WETH, usdg);
        uint256 vaultUsdgAmount = vault.usdqAmounts(WETH);
        uint256 maxUsdgAmount = vault.maxUsdqAmounts(WETH);
        return maxUsdgAmount == 0 || vaultUsdgAmount + usdgAmount < maxUsdgAmount;
    }

    function checkReward() public view override returns (uint256) {
        Reward[] memory rewards = _pendingRewards();
        uint256 estimatedTotalReward = rewardToken.balanceOf(address(this));
        for (uint256 i = 0; i < rewards.length; i++) {
            address reward = rewards[i].reward;
            if (reward == address(rewardToken)) {
                estimatedTotalReward += rewards[i].amount;
            } else if (reward > address(0)) {
                uint256 balance = IERC20(reward).balanceOf(address(this));
                uint256 amount = balance + rewards[i].amount;
                address swapPair = rewardSwapPairs[rewards[i].reward].swapPair;
                if (amount > 0 && swapPair > address(0)) {
                    estimatedTotalReward += DexLibrary.estimateConversionThroughPair(
                        amount,
                        reward,
                        address(rewardToken),
                        IPair(swapPair),
                        rewardSwapPairs[rewards[i].reward].swapFee
                    );
                }
            }
        }
        return estimatedTotalReward;
    }

    function _pendingRewards() internal view returns (Reward[] memory) {
        Reward[] memory rewards = new Reward[](1);
        rewards[0].reward = WETH;
        rewards[0].amount = feeQlpTracker.claimable(address(this));
        return rewards;
    }

    function totalDeposits() public view override returns (uint256) {
        return IRewardTracker(feeQlpTracker).stakedAmounts(address(this));
    }

    /**
     * @notice Estimate recoverable balance after withdraw fee
     * @return deposit tokens after withdraw fee
     */
    function estimateDeployedBalance() external view override returns (uint256) {
        uint256 depositBalance = totalDeposits();
        uint256 withdrawFee = calculateWithdrawFee(depositBalance);
        return depositBalance - withdrawFee;
    }

    function rescueDeployedFunds(uint256, bool) external view override onlyOwner {
        revert("QlpStrategy::Unsupported operation");
    }
}
