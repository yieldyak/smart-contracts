// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../YakStrategy.sol";
import "../../interfaces/IPair.sol";
import "../../lib/DexLibrary.sol";
import "./interfaces/ICurveRewardsGauge.sol";
import "./interfaces/ICurveRewardsClaimer.sol";
import "./lib/CurveSwap.sol";

/**
 * @notice Strategy for Curve LP
 */
contract CurveStrategyForLPV2 is YakStrategy {
    using SafeMath for uint256;

    struct Reward {
        address reward;
        address swapPair;
    }

    ICurveRewardsGauge public stakingContract;
    address public rewardContract;
    IPair private swapPairRewardZap;
    function(uint256, address, address, CurveSwap.Settings memory) internal returns (uint256) _zapToDepositToken;
    CurveSwap.Settings private zapSettings;
    Reward[] public rewards;

    constructor(
        string memory _name,
        address _depositToken,
        address _rewardToken,
        address _stakingContract,
        address _rewardContract,
        address _swapPairRewardZap,
        Reward[] memory _rewards,
        CurveSwap.Settings memory _zapSettings,
        address _timelock,
        StrategySettings memory _strategySettings
    ) YakStrategy(_strategySettings) {
        name = _name;
        devAddr = msg.sender;
        depositToken = IERC20(_depositToken);
        rewardToken = IERC20(_rewardToken);
        stakingContract = ICurveRewardsGauge(_stakingContract);
        rewardContract = _rewardContract;
        require(_swapPairRewardZap > address(0), "Swap pair 0 is necessary but not supplied");
        require(
            IPair(_swapPairRewardZap).token0() == _zapSettings.zapToken ||
                IPair(_swapPairRewardZap).token1() == _zapSettings.zapToken,
            "Swap pair supplied does not have the reward token as one of it's pair"
        );
        for (uint256 i = 0; i < _rewards.length; i++) {
            rewards.push(_rewards[i]);
        }
        swapPairRewardZap = IPair(_swapPairRewardZap);
        _zapToDepositToken = CurveSwap.setZap(_zapSettings);
        zapSettings = _zapSettings;
        setAllowances();
        updateMaxSwapSlippage(_zapSettings.maxSlippage);
        updateDepositsEnabled(true);
        transferOwnership(_timelock);
        emit Reinvest(0, 0);
    }

    function setAllowances() public override onlyOwner {
        depositToken.approve(address(stakingContract), type(uint256).max);
        IERC20(zapSettings.zapToken).approve(zapSettings.zapContract, type(uint256).max);
    }

    function addReward(address rewardToken, address swapPair) public onlyDev {
        rewards.push(Reward({reward: rewardToken, swapPair: swapPair}));
    }

    function removeReward(address rewardToken) public onlyDev {
        uint256 index = 0;
        for (uint256 i = 0; i < rewards.length; i++) {
            if (rewards[i].reward == rewardToken) {
                index = i;
                break;
            }
        }
        require(rewards[index].reward == rewardToken, "CurveStrategyForLPV2::Reward not found!");
        rewards[index] = rewards[rewards.length - 1];
        rewards.pop();
    }

    function updateMaxSwapSlippage(uint256 slippageBips) public onlyDev {
        zapSettings.maxSlippage = slippageBips;
    }

    function deposit(uint256 amount) external override {
        _deposit(msg.sender, amount);
    }

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

    function _deposit(address account, uint256 amount) private onlyAllowedDeposits {
        require(DEPOSITS_ENABLED == true, "CurveStrategyForLPV2::_deposit");
        if (MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST > 0) {
            uint256[] memory amounts = _claimRewards();
            uint256 unclaimedRewards = _estimateRewardConvertedToAvax(amounts);
            if (unclaimedRewards > MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST) {
                _reinvest(amounts);
            }
        }
        require(depositToken.transferFrom(msg.sender, address(this), amount));
        _stakeDepositTokens(amount);
        _mint(account, getSharesForDepositTokens(amount));
        totalDeposits = totalDeposits.add(amount);
        emit Deposit(account, amount);
    }

    function withdraw(uint256 amount) external override {
        uint256 depositTokenAmount = getDepositTokensForShares(amount);
        require(depositTokenAmount > 0, "CurveStrategyForLPV2::withdraw");
        _withdrawDepositTokens(depositTokenAmount);
        _safeTransfer(address(depositToken), msg.sender, depositTokenAmount);
        _burn(msg.sender, amount);
        totalDeposits = totalDeposits.sub(depositTokenAmount);
        emit Withdraw(msg.sender, depositTokenAmount);
    }

    function _withdrawDepositTokens(uint256 amount) private {
        stakingContract.withdraw(amount);
    }

    function reinvest() external override onlyEOA {
        uint256[] memory amounts = _claimRewards();
        uint256 unclaimedRewards = _estimateRewardConvertedToAvax(amounts);
        require(unclaimedRewards >= MIN_TOKENS_TO_REINVEST, "CurveStrategyForLPV2::reinvest");
        _reinvest(amounts);
    }

    function _claimRewards() private returns (uint256[] memory) {
        ICurveRewardsClaimer(stakingContract.reward_contract()).get_reward();
        stakingContract.claim_rewards();
        uint256 rewardsCount = rewards.length;
        uint256[] memory amounts = new uint256[](rewardsCount);
        for (uint256 i = 0; i < rewardsCount; i++) {
            amounts[i] = IERC20(rewards[i].reward).balanceOf(address(this));
        }
        return amounts;
    }

    function _estimateRewardConvertedToAvax(uint256[] memory amounts) private view returns (uint256) {
        uint256 estimatedWFTM = 0;
        for (uint256 i = 0; i < rewards.length; i++) {
            if (rewards[i].reward != address(rewardToken)) {
                estimatedWFTM = estimatedWFTM.add(
                    DexLibrary.estimateConversionThroughPair(
                        amounts[i],
                        address(rewards[i].reward),
                        address(rewardToken),
                        IPair(rewards[i].swapPair)
                    )
                );
            } else {
                estimatedWFTM = estimatedWFTM.add(amounts[i]);
            }
        }
        return estimatedWFTM;
    }

    /**
     * @notice Reinvest rewards from staking contract to deposit tokens
     * @dev Reverts if the expected amount of tokens are not returned from `stableSwap`
     */
    function _reinvest(uint256[] memory amounts) private {
        uint256 amount = _convertRewardIntoWFTM(amounts);

        uint256 devFee = amount.mul(DEV_FEE_BIPS).div(BIPS_DIVISOR);
        if (devFee > 0) {
            _safeTransfer(address(rewardToken), devAddr, devFee);
        }

        uint256 reinvestFee = amount.mul(REINVEST_REWARD_BIPS).div(BIPS_DIVISOR);
        if (reinvestFee > 0) {
            _safeTransfer(address(rewardToken), msg.sender, reinvestFee);
        }

        uint256 depositTokenAmount = _zapToDepositToken(
            amount.sub(devFee).sub(reinvestFee),
            address(rewardToken),
            address(depositToken),
            zapSettings
        );

        _stakeDepositTokens(depositTokenAmount);
        totalDeposits = totalDeposits.add(depositTokenAmount);

        emit Reinvest(totalDeposits, totalSupply);
    }

    function _convertRewardIntoWFTM(uint256[] memory amounts) private returns (uint256) {
        uint256 ftmAmount = 0;
        for (uint256 i = 0; i < rewards.length; i++) {
            if (rewards[i].reward != address(rewardToken)) {
                if (amounts[i] > 0) {
                    ftmAmount = ftmAmount.add(
                        DexLibrary.swap(
                            amounts[i],
                            address(rewards[i].reward),
                            address(rewardToken),
                            IPair(rewards[i].swapPair)
                        )
                    );
                }
            } else {
                ftmAmount = ftmAmount.add(amounts[i]);
            }
        }
        return ftmAmount;
    }

    function _stakeDepositTokens(uint256 amount) private {
        require(amount > 0, "CurveStrategyForLPV2::_stakeDepositTokens");
        stakingContract.deposit(amount);
    }

    /**
     * @notice Safely transfer using an anonymosu ERC20 token
     * @dev Requires token to return true on transfer
     * @param token address
     * @param to recipient address
     * @param value amount
     */
    function _safeTransfer(
        address token,
        address to,
        uint256 value
    ) private {
        require(IERC20(token).transfer(to, value), "CurveStrategyForLPV2::TRANSFER_FROM_FAILED");
    }

    function checkReward() public view override returns (uint256) {
        uint256 rewardsCount = rewards.length;
        uint256[] memory amounts = new uint256[](rewardsCount);
        for (uint256 i = 0; i < rewardsCount; i++) {
            amounts[i] = _calculateRewards(rewards[i].reward);
        }

        return _estimateRewardConvertedToAvax(amounts);
    }

    function _calculateRewards(address _rewardToken) public view returns (uint256) {
        address rewardContractAddress = address(0);
        if (rewardContract > address(0)) {
            rewardContractAddress = rewardContract;
        } else {
            rewardContractAddress = stakingContract.reward_contract();
        }

        uint256 lastRewardUpdateTime = ICurveRewardsClaimer(rewardContractAddress).last_update_time();
        DataTypes.RewardToken memory rewardToken = ICurveRewardsClaimer(rewardContractAddress).reward_data(
            _rewardToken
        );

        uint256 gaugeBalance = IERC20(_rewardToken).balanceOf(address(stakingContract));
        uint256 unclaimedTotal = (block.timestamp - lastRewardUpdateTime) * rewardToken.rate;
        uint256 tokenBalance = gaugeBalance.add(unclaimedTotal);

        uint256 dI = uint256(10e18).mul(tokenBalance.sub(stakingContract.reward_balances(_rewardToken))).div(
            stakingContract.totalSupply()
        );
        uint256 integral = stakingContract.reward_integral(_rewardToken) + dI;
        uint256 integralFor = stakingContract.reward_integral_for(_rewardToken, address(this));

        uint256 strategyUnclaimed = 0;
        if (integralFor < integral) {
            strategyUnclaimed = stakingContract.balanceOf(address(this)).mul(integral.sub(integralFor)).div(10e18);
        }
        uint256 strategyClaimed = stakingContract.claimable_reward(address(this), _rewardToken);
        return strategyClaimed.add(strategyUnclaimed);
    }

    function estimateDeployedBalance() external view override returns (uint256) {
        return stakingContract.balanceOf(address(this));
    }

    function rescueDeployedFunds(uint256 minReturnAmountAccepted, bool disableDeposits) external override onlyOwner {
        uint256 balanceBefore = depositToken.balanceOf(address(this));
        stakingContract.withdraw(stakingContract.balanceOf(address(this)));
        uint256 balanceAfter = depositToken.balanceOf(address(this));
        require(
            balanceAfter.sub(balanceBefore) >= minReturnAmountAccepted,
            "CurveStrategyForLPV2::rescueDeployedFunds"
        );
        totalDeposits = balanceAfter;
        emit Reinvest(totalDeposits, totalSupply);
        if (DEPOSITS_ENABLED == true && disableDeposits == true) {
            updateDepositsEnabled(false);
        }
    }
}
