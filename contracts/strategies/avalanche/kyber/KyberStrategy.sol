// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../../YakStrategyV2.sol";
import "../../../lib/DexLibrary.sol";
import "../../../lib/SafeERC20.sol";
import "../../../interfaces/IPair.sol";

import "./interfaces/IKyberPair.sol";
import "./interfaces/IKyberFairLaunchV2.sol";
import "./interfaces/IKyberRewardLockerV2.sol";
import "./lib/KyberDexLibrary.sol";

/**
 * @notice KyberStrategy
 */
contract KyberStrategy is YakStrategyV2 {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IWAVAX internal constant WAVAX = IWAVAX(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);
    address internal constant KNC = 0x39fC9e94Caeacb435842FADeDeCB783589F50f5f;

    struct Reward {
        address reward;
        uint256 amount;
    }

    struct RewardSwapPairs {
        address reward;
        address swapPair;
    }

    struct SwapPairs {
        address token0;
        address token1;
    }

    IKyberFairLaunchV2 public immutable stakingContract;
    IKyberRewardLockerV2 public immutable rewardLocker;
    uint256 public immutable PID;

    // reward -> swapPair
    mapping(address => address) public rewardSwapPairs;
    address[] public supportedRewards;
    uint256 public rewardCount;

    address private swapPairToken0;
    address private swapPairToken1;

    event AddReward(address rewardToken, address swapPair);
    event RemoveReward(address rewardToken);

    constructor(
        string memory _name,
        SwapPairs memory _swapPairs,
        RewardSwapPairs[] memory _rewardSwapPairs,
        address _stakingContract,
        uint256 _pid,
        address _timelock,
        StrategySettings memory _strategySettings
    ) YakStrategyV2(_strategySettings) {
        name = _name;
        devAddr = 0x2D580F9CF2fB2D09BC411532988F2aFdA4E7BefF;
        stakingContract = IKyberFairLaunchV2(_stakingContract);
        rewardLocker = IKyberRewardLockerV2(IKyberFairLaunchV2(_stakingContract).rewardLocker());
        PID = _pid;

        for (uint256 i = 0; i < _rewardSwapPairs.length; i++) {
            _addReward(_rewardSwapPairs[i].reward, _rewardSwapPairs[i].swapPair);
        }
        assignSwapPairSafely(_swapPairs);

        updateDepositsEnabled(true);
        transferOwnership(_timelock);
        emit Reinvest(0, 0);
    }

    /**
     * @notice Initialization helper for Pair deposit tokens
     * @dev Checks that selected Pairs are valid for trading reward tokens
     * @dev Assigns values to IPair(swapPairToken0) and IPair(swapPairToken1)
     */
    function assignSwapPairSafely(SwapPairs memory _swapPairs) private {
        if (
            address(WAVAX) != IPair(address(depositToken)).token0() &&
            address(WAVAX) != IPair(address(depositToken)).token1()
        ) {
            // deployment checks for non-pool2
            require(_swapPairs.token0 > address(0), "Swap pair 0 is necessary but not supplied");
            require(_swapPairs.token1 > address(0), "Swap pair 1 is necessary but not supplied");
            swapPairToken0 = _swapPairs.token0;
            swapPairToken1 = _swapPairs.token1;
            require(
                IPair(swapPairToken0).token0() == address(WAVAX) || IPair(swapPairToken0).token1() == address(WAVAX),
                "Swap pair supplied does not have the reward token as one of it's pair"
            );
            require(
                IPair(swapPairToken0).token0() == IPair(address(depositToken)).token0() ||
                    IPair(swapPairToken0).token1() == IPair(address(depositToken)).token0(),
                "Swap pair 0 supplied does not match the pair in question"
            );
            require(
                IPair(swapPairToken1).token0() == IPair(address(depositToken)).token1() ||
                    IPair(swapPairToken1).token1() == IPair(address(depositToken)).token1(),
                "Swap pair 1 supplied does not match the pair in question"
            );
        } else if (address(WAVAX) == IPair(address(depositToken)).token0()) {
            swapPairToken1 = address(depositToken);
        } else if (address(WAVAX) == IPair(address(depositToken)).token1()) {
            swapPairToken0 = address(depositToken);
        }
    }

    function addReward(address _rewardToken, address _swapPair) public onlyDev {
        _addReward(_rewardToken, _swapPair);
    }

    function _addReward(address _rewardToken, address _swapPair) internal {
        if (_rewardToken != address(rewardToken)) {
            require(
                KyberDexLibrary.checkSwapPairCompatibility(IKyberPair(_swapPair), _rewardToken, address(rewardToken)),
                "VariableRewardsStrategy::Swap pair does not contain reward token"
            );
        }
        rewardSwapPairs[_rewardToken] = _swapPair;
        supportedRewards.push(_rewardToken);
        rewardCount = rewardCount.add(1);
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
        rewardCount = rewardCount.sub(1);
        emit RemoveReward(_rewardToken);
    }

    receive() external payable {
        require(
            msg.sender == address(rewardLocker) || msg.sender == owner() || msg.sender == address(devAddr),
            "not allowed"
        );
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
    function depositWithPermit(
        uint256 _amount,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external override {
        depositToken.permit(msg.sender, address(this), _amount, _deadline, _v, _r, _s);
        _deposit(msg.sender, _amount);
    }

    function depositFor(address _account, uint256 _amount) external override {
        _deposit(_account, _amount);
    }

    function _deposit(address _account, uint256 _amount) internal {
        require(DEPOSITS_ENABLED == true, "VariableRewardsStrategy::Deposits disabled");
        if (MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST > 0) {
            uint256 estimatedTotalReward = checkReward();
            if (estimatedTotalReward > MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST) {
                _reinvest(true);
            }
        }
        require(
            depositToken.transferFrom(msg.sender, address(this), _amount),
            "VariableRewardsStrategy::Deposit token transfer failed"
        );
        _mint(_account, getSharesForDepositTokens(_amount));
        _stakeDepositTokens(_amount);
        emit Deposit(_account, _amount);
    }

    function withdraw(uint256 _amount) external override {
        uint256 depositTokenAmount = getDepositTokensForShares(_amount);
        require(depositTokenAmount > 0, "VariableRewardsStrategy::Withdraw amount too low");
        stakingContract.withdraw(PID, depositTokenAmount);
        depositToken.safeTransfer(msg.sender, depositTokenAmount);
        _burn(msg.sender, _amount);
        emit Withdraw(msg.sender, depositTokenAmount);
    }

    function reinvest() external override onlyEOA {
        _reinvest(false);
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
                    if (reward == KNC) {
                        amount = KyberDexLibrary.swap(amount, reward, address(rewardToken), IKyberPair(swapPair));
                    } else {
                        amount = DexLibrary.swap(amount, reward, address(rewardToken), IPair(swapPair));
                    }
                    avaxAmount = avaxAmount.add(amount);
                }
            }
        }
        return avaxAmount;
    }

    /**
     * @notice Reinvest rewards from staking contract to deposit tokens
     * @dev Reverts if the expected amount of tokens are not returned from the staking contract
     */
    function _reinvest(bool userDeposit) private {
        stakingContract.harvest(PID);
        rewardLocker.vestCompletedSchedulesForMultipleTokens(stakingContract.getRewardTokens());

        uint256 amount = _convertRewardsIntoWAVAX();
        if (!userDeposit) {
            require(amount >= MIN_TOKENS_TO_REINVEST, "VariableRewardsStrategy::Reinvest amount too low");
        }

        uint256 devFee = amount.mul(DEV_FEE_BIPS).div(BIPS_DIVISOR);
        if (devFee > 0) {
            rewardToken.safeTransfer(devAddr, devFee);
        }

        uint256 reinvestFee = amount.mul(REINVEST_REWARD_BIPS).div(BIPS_DIVISOR);
        if (reinvestFee > 0) {
            rewardToken.safeTransfer(msg.sender, reinvestFee);
        }

        uint256 depositTokenAmount = _convertRewardTokenToDepositToken(amount.sub(devFee).sub(reinvestFee));

        _stakeDepositTokens(depositTokenAmount);
        emit Reinvest(totalDeposits(), totalSupply);
    }

    function _convertRewardTokenToDepositToken(uint256 _fromAmount) internal virtual returns (uint256 toAmount) {
        toAmount = KyberDexLibrary.convertRewardTokensToDepositTokens(
            _fromAmount,
            address(rewardToken),
            address(depositToken),
            IKyberPair(swapPairToken0),
            IKyberPair(swapPairToken1)
        );
    }

    function _stakeDepositTokens(uint256 _amount) private {
        require(_amount > 0, "VariableRewardsStrategy::Stake amount too low");
        depositToken.approve(address(stakingContract), _amount);
        stakingContract.deposit(PID, _amount, false);
        depositToken.approve(address(stakingContract), 0);
    }

    function _pendingRewards() internal view virtual returns (Reward[] memory) {
        address[] memory rewardTokens = stakingContract.getRewardTokens();
        uint256[] memory amounts = stakingContract.pendingRewards(PID, address(this));
        Reward[] memory pendingRewards = new Reward[](rewardTokens.length);
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address reward = rewardTokens[i] > address(0) ? rewardTokens[i] : address(WAVAX);
            pendingRewards[i] = Reward({reward: reward, amount: amounts[i]});
        }
        return pendingRewards;
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
                    if (reward == KNC) {
                        amount = KyberDexLibrary.estimateConversionThroughPair(
                            amount,
                            reward,
                            address(WAVAX),
                            IKyberPair(swapPair)
                        );
                    } else {
                        amount = DexLibrary.estimateConversionThroughPair(
                            amount,
                            reward,
                            address(WAVAX),
                            IPair(swapPair)
                        );
                    }
                    estimatedTotalReward = estimatedTotalReward.add(amount);
                }
            }
        }
        return estimatedTotalReward;
    }

    function totalDeposits() public view override returns (uint256) {
        (uint256 amount, , ) = stakingContract.getUserInfo(PID, address(this));
        return amount;
    }

    /**
     * @notice Estimate recoverable balance after withdraw fee
     * @return deposit tokens after withdraw fee
     */
    function estimateDeployedBalance() external view override returns (uint256) {
        return totalDeposits();
    }

    function rescueDeployedFunds(
        uint256 _minReturnAmountAccepted,
        bool /*_disableDeposits*/
    ) external override onlyOwner {
        uint256 balanceBefore = depositToken.balanceOf(address(this));
        depositToken.approve(address(stakingContract), 0);
        stakingContract.emergencyWithdraw(PID);
        uint256 balanceAfter = depositToken.balanceOf(address(this));
        require(
            balanceAfter.sub(balanceBefore) >= _minReturnAmountAccepted,
            "VariableRewardsStrategy::Emergency withdraw minimum return amount not reached"
        );
        emit Reinvest(totalDeposits(), totalSupply);
        if (DEPOSITS_ENABLED == true) {
            updateDepositsEnabled(false);
        }
    }
}
