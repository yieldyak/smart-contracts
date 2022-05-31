// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../YakStrategyV3.sol";
import "../interfaces/IPair.sol";
import "../lib/DexLibrary.sol";
import "../lib/SafeERC20.sol";

/**
 * @notice VariableRewardsStrategy
 */
abstract contract VariableRewardsStrategyV2 is YakStrategyV3 {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IWAVAX internal constant WAVAX = IWAVAX(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);
    uint256 public constant SLIPPAGE_BIPS_DIVISOR = 10000;

    struct Reward {
        address reward;
        uint256 amount;
    }

    struct RewardSwapPairs {
        address reward;
        address swapPair;
    }

    // reward -> swapPair
    mapping(address => address) public rewardSwapPairs;
    address[] public supportedRewards;
    uint256 public rewardCount;

    event AddReward(address rewardToken, address swapPair);
    event RemoveReward(address rewardToken);

    constructor(
        RewardSwapPairs[] memory _rewardSwapPairs,
        BaseSettings memory _baseSettings,
        StrategySettings memory _strategySettings
    ) YakStrategyV3(_baseSettings, _strategySettings) {
        devAddr = 0x2D580F9CF2fB2D09BC411532988F2aFdA4E7BefF;

        for (uint256 i = 0; i < _rewardSwapPairs.length; i++) {
            _addReward(_rewardSwapPairs[i].reward, _rewardSwapPairs[i].swapPair);
        }

        emit Reinvest(0, 0);
    }

    /*//////////////////////////////////////////////////////////////
                            ABSTRACT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _depositToStakingContract(uint256 _amount) internal virtual;

    function _withdrawFromStakingContract(uint256 _amount) internal virtual returns (uint256 withdrawAmount);

    function _pendingRewards() internal view virtual returns (Reward[] memory);

    function _getRewards() internal virtual;

    function _convertRewardTokenToDepositToken(uint256 _fromAmount) internal virtual returns (uint256 toAmount);

    function _emergencyWithdraw() internal virtual;

    /*//////////////////////////////////////////////////////////////
                            VIRTUAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculate deposit fee of underlying farm
     * @dev Override if deposit fee is calculated dynamically
     */
    function _calculateDepositFee(uint256 _amount) internal view virtual returns (uint256) {
        uint256 depositFeeBips = _getDepositFeeBips();
        return (_amount * depositFeeBips) / _bip();
    }

    /**
     * @notice Withdraw fee bips from underlying farm
     */
    function _getDepositFeeBips() internal view virtual returns (uint256) {
        return 0;
    }

    /**
     * @notice Calculate withdraw fee of underlying farm
     * @dev Override if withdraw fee is calculated dynamically
     * @dev Important: Do not override if withdraw fee is deducted from the amount returned by _withdrawFromStakingContract
     */
    function _calculateWithdrawFee(uint256 _amount) internal view virtual returns (uint256) {
        uint256 withdrawFeeBips = _getWithdrawFeeBips();
        return _amount.mul(withdrawFeeBips).div(_bip());
    }

    /**
     * @notice Withdraw fee bips from underlying farm
     * @dev Important: Do not override if withdraw fee is deducted from the amount returned by _withdrawFromStakingContract
     */
    function _getWithdrawFeeBips() internal view virtual returns (uint256) {
        return 0;
    }

    function _bip() internal view virtual returns (uint256) {
        return 10000;
    }

    function _getMaxSlippageBips() internal view virtual returns (uint256) {
        return 0;
    }

    /*//////////////////////////////////////////////////////////////
                                DEPOSIT
    //////////////////////////////////////////////////////////////*/

    function deposit(uint256 _assets, uint256) internal override {
        if (MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST > 0) {
            uint256 estimatedTotalReward = checkReward();
            if (estimatedTotalReward > MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST) {
                _reinvest(true);
            }
        }
        _stakeDepositTokens(_assets);
    }

    function _stakeDepositTokens(uint256 _amount) private {
        require(_amount > 0, "VariableRewardsStrategy::Stake amount too low");
        _depositToStakingContract(_amount);
    }

    function previewDeposit(uint256 _assets) public view override returns (uint256) {
        uint256 depositFee = _calculateDepositFee(_assets);
        return convertToShares(_assets - depositFee);
    }

    function previewMint(uint256 _shares) public view override returns (uint256) {
        uint256 assets = convertToAssets(_shares);
        uint256 depositFee = _calculateDepositFee(assets);
        return assets + depositFee;
    }

    function calculateDepositFee(uint256 _amount) internal view returns (uint256) {
        return _calculateDepositFee(_amount);
    }

    /*//////////////////////////////////////////////////////////////
                              WITHDRAW
    //////////////////////////////////////////////////////////////*/

    function withdraw(uint256 assets, uint256) internal override returns (uint256) {
        return _withdrawFromStakingContract(assets);
    }

    function previewWithdraw(uint256 _assets) public view override returns (uint256) {
        uint256 withdrawFee = _calculateWithdrawFee(_assets);
        uint256 maxSlippage = _calculateMaxSlippage(_assets);
        return convertToShares(_assets + withdrawFee + maxSlippage);
    }

    function previewRedeem(uint256 _shares) public view override returns (uint256) {
        uint256 assets = convertToAssets(_shares);
        uint256 withdrawFee = _calculateWithdrawFee(assets);
        uint256 maxSlippage = _calculateMaxSlippage(assets);
        return assets - withdrawFee - maxSlippage;
    }

    function _calculateMaxSlippage(uint256 amount) internal view virtual returns (uint256) {
        uint256 slippageBips = _getMaxSlippageBips();
        return (amount * slippageBips) / SLIPPAGE_BIPS_DIVISOR;
    }

    /*//////////////////////////////////////////////////////////////
                              REINVEST
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Reinvest rewards from staking contract to deposit tokens
     * @dev Reverts if the expected amount of tokens are not returned from the staking contract
     */
    function _reinvest(bool userDeposit) internal override {
        _getRewards();
        uint256 amount = _convertRewardsIntoWAVAX();
        if (!userDeposit) {
            require(amount >= MIN_TOKENS_TO_REINVEST, "VariableRewardsStrategy::Reinvest amount too low");
        }

        uint256 devFee = amount.mul(DEV_FEE_BIPS).div(BIPS_DIVISOR);
        if (devFee > 0) {
            IERC20(rewardToken).safeTransfer(devAddr, devFee);
        }

        uint256 reinvestFee = amount.mul(REINVEST_REWARD_BIPS).div(BIPS_DIVISOR);
        if (reinvestFee > 0) {
            IERC20(rewardToken).safeTransfer(msg.sender, reinvestFee);
        }

        uint256 depositTokenAmount = _convertRewardTokenToDepositToken(amount.sub(devFee).sub(reinvestFee));

        _stakeDepositTokens(depositTokenAmount);
        emit Reinvest(totalDeposits(), totalSupply());
    }

    function _convertRewardsIntoWAVAX() private returns (uint256) {
        uint256 avaxAmount = WAVAX.balanceOf(address(this));
        uint256 count = supportedRewards.length;
        for (uint256 i = 0; i < count; i++) {
            address reward = supportedRewards[i];
            if (reward == address(WAVAX)) {
                uint256 balance = address(this).balance;
                if (balance > 0) {
                    WAVAX.deposit{value: balance}();
                    avaxAmount = avaxAmount.add(balance);
                }
                continue;
            }
            uint256 amount = IERC20(reward).balanceOf(address(this));
            if (amount > 0) {
                address swapPair = rewardSwapPairs[reward];
                if (swapPair > address(0)) {
                    avaxAmount = avaxAmount.add(DexLibrary.swap(amount, reward, rewardToken, IPair(swapPair)));
                }
            }
        }
        return avaxAmount;
    }

    function checkReward() public view override returns (uint256) {
        Reward[] memory rewards = _pendingRewards();
        uint256 estimatedTotalReward = WAVAX.balanceOf(address(this));
        estimatedTotalReward.add(address(this).balance);
        for (uint256 i = 0; i < rewards.length; i++) {
            address reward = rewards[i].reward;
            if (reward == address(WAVAX)) {
                estimatedTotalReward = estimatedTotalReward.add(rewards[i].amount);
            } else {
                uint256 balance = IERC20(reward).balanceOf(address(this));
                uint256 amount = balance.add(rewards[i].amount);
                address swapPair = rewardSwapPairs[rewards[i].reward];
                if (amount > 0 && swapPair > address(0)) {
                    estimatedTotalReward = estimatedTotalReward.add(
                        DexLibrary.estimateConversionThroughPair(amount, reward, address(WAVAX), IPair(swapPair))
                    );
                }
            }
        }
        return estimatedTotalReward;
    }

    /*//////////////////////////////////////////////////////////////
                             ADMIN
    //////////////////////////////////////////////////////////////*/

    function addReward(address _rewardToken, address _swapPair) public onlyDev {
        _addReward(_rewardToken, _swapPair);
    }

    function _addReward(address _rewardToken, address _swapPair) internal {
        if (_rewardToken != rewardToken) {
            require(
                DexLibrary.checkSwapPairCompatibility(IPair(_swapPair), _rewardToken, rewardToken),
                "VariableRewardsStrategy::Swap pair does not contain reward token"
            );
        }
        rewardSwapPairs[_rewardToken] = _swapPair;
        supportedRewards.push(_rewardToken);
        rewardCount = rewardCount + 1;
        emit AddReward(_rewardToken, _swapPair);
    }

    function removeReward(address _rewardToken) public onlyDev {
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

    function _rescueDeployedFunds(uint256 _minReturnAmountAccepted) internal override {
        uint256 balanceBefore = IERC20(asset).balanceOf(address(this));
        _emergencyWithdraw();
        uint256 balanceAfter = IERC20(asset).balanceOf(address(this));
        require(
            balanceAfter.sub(balanceBefore) >= _minReturnAmountAccepted,
            "VariableRewardsStrategy::Emergency withdraw minimum return amount not reached"
        );
        emit Reinvest(totalDeposits(), totalSupply());
        if (DEPOSITS_ENABLED == true) {
            updateDepositsEnabled(false);
        }
    }
}
