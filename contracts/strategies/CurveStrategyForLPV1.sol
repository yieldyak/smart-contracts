pragma experimental ABIEncoderV2;
// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "../YakStrategy.sol";
import "../interfaces/ICurveStableSwapAave.sol";
import "../interfaces/ICurveCryptoSwap.sol";
import "../interfaces/ICurveRewardsGauge.sol";
import "../interfaces/ICurveRewardsClaimer.sol";
import "../interfaces/IPair.sol";
import "../lib/DexLibrary.sol";

/**
 * @notice Strategy for Curve LP
 */
contract CurveStrategyForLPV1 is YakStrategy {
    using SafeMath for uint256;

    enum PoolType {
        AAVE,
        CRYPTO
    }

    struct StrategySettings {
        uint256 minTokensToReinvest;
        uint256 adminFeeBips;
        uint256 devFeeBips;
        uint256 reinvestRewardBips;
    }

    struct ZapSettings {
        PoolType poolType;
        address zapToken;
        address zapContract;
        uint256 zapTokenIndex;
        uint256 maxSlippage;
    }

    ICurveRewardsGauge public stakingContract;
    IPair private swapPairWavaxZap;
    address private swapPairCrvAvax = address(0);
    bytes private constant zeroBytes = new bytes(0);
    function(uint256) internal returns (uint256) _zapToDepositToken;
    address private constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    address private constant CRV = 0x47536F17F4fF30e64A96a7555826b8f9e66ec468;
    ZapSettings private zapSettings;

    constructor(
        string memory _name,
        address _depositToken,
        address _stakingContract,
        address _swapPairWavaxZap,
        address _swapPairCrvAvax,
        address _timelock,
        StrategySettings memory _strategySettings,
        ZapSettings memory _zapSettings
    ) {
        name = _name;
        devAddr = msg.sender;
        depositToken = IERC20(_depositToken);
        rewardToken = IERC20(WAVAX);
        stakingContract = ICurveRewardsGauge(_stakingContract);

        swapPairCrvAvax = _swapPairCrvAvax;
        require(_swapPairWavaxZap > address(0), "Swap pair 0 is necessary but not supplied");
        require(
            IPair(_swapPairWavaxZap).token0() == _zapSettings.zapToken ||
                IPair(_swapPairWavaxZap).token1() == _zapSettings.zapToken,
            "Swap pair supplied does not have the reward token as one of it's pair"
        );
        swapPairWavaxZap = IPair(_swapPairWavaxZap);
        if (_zapSettings.poolType == PoolType.AAVE) {
            require(
                _zapSettings.zapToken ==
                    ICurveStableSwapAave(_zapSettings.zapContract).underlying_coins(_zapSettings.zapTokenIndex),
                "Wrong zap token index"
            );
            _zapToDepositToken = _zapToAaveLP;
        } else if (_zapSettings.poolType == PoolType.CRYPTO) {
            require(
                _zapSettings.zapToken ==
                    ICurveCryptoSwap(_zapSettings.zapContract).underlying_coins(_zapSettings.zapTokenIndex),
                "Wrong zap token index"
            );
            _zapToDepositToken = _zapToCryptoLP;
        }
        zapSettings = _zapSettings;

        setAllowances();
        updateMaxSwapSlippage(_zapSettings.maxSlippage);
        updateMinTokensToReinvest(_strategySettings.minTokensToReinvest);
        updateAdminFee(_strategySettings.adminFeeBips);
        updateDevFee(_strategySettings.devFeeBips);
        updateReinvestReward(_strategySettings.reinvestRewardBips);
        updateDepositsEnabled(true);
        transferOwnership(_timelock);

        emit Reinvest(0, 0);
    }

    function setAllowances() public override onlyOwner {
        depositToken.approve(address(stakingContract), type(uint256).max);
        IERC20(zapSettings.zapToken).approve(zapSettings.zapContract, type(uint256).max);
    }

    function updateCrvAvaxSwapPair(address swapPair) public onlyDev {
        swapPairCrvAvax = swapPair;
    }

    function updateMaxSwapSlippage(uint256 slippageBips) public onlyDev {
        zapSettings.maxSlippage = slippageBips;
    }

    function _zapToAaveLP(uint256 amount) private returns (uint256) {
        uint256 zapTokenAmount = DexLibrary.swap(amount, WAVAX, zapSettings.zapToken, swapPairWavaxZap);
        uint256[3] memory amounts = [uint256(0), uint256(0), uint256(0)];
        amounts[zapSettings.zapTokenIndex] = zapTokenAmount;
        uint256 expectedAmount = ICurveStableSwapAave(zapSettings.zapContract).calc_token_amount(amounts, true);
        uint256 slippage = expectedAmount.mul(zapSettings.maxSlippage).div(BIPS_DIVISOR);
        return ICurveStableSwapAave(zapSettings.zapContract).add_liquidity(amounts, expectedAmount.sub(slippage), true);
    }

    function _zapToCryptoLP(uint256 amount) private returns (uint256) {
        uint256 zapTokenAmount = DexLibrary.swap(amount, WAVAX, zapSettings.zapToken, swapPairWavaxZap);
        uint256[5] memory amounts = [uint256(0), uint256(0), uint256(0), uint256(0), uint256(0)];
        amounts[zapSettings.zapTokenIndex] = zapTokenAmount;
        uint256 expectedAmount = ICurveCryptoSwap(zapSettings.zapContract).calc_token_amount(amounts, true);
        uint256 slippage = expectedAmount.mul(zapSettings.maxSlippage).div(BIPS_DIVISOR);
        ICurveCryptoSwap(zapSettings.zapContract).add_liquidity(amounts, expectedAmount.sub(slippage));
        return depositToken.balanceOf(address(this));
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
        require(DEPOSITS_ENABLED == true, "CurveStrategyForAv3CRVV1::_deposit");
        if (MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST > 0) {
            (uint256 pendingAvaxRewards, uint256 pendingCrvRewards) = _claimRewards();
            uint256 unclaimedRewards = _estimateRewardConvertedToAvax(pendingAvaxRewards, pendingCrvRewards);
            if (unclaimedRewards > MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST) {
                _reinvest(pendingAvaxRewards, pendingCrvRewards);
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
        if (depositTokenAmount > 0) {
            _withdrawDepositTokens(depositTokenAmount);
            _safeTransfer(address(depositToken), msg.sender, depositTokenAmount);
            _burn(msg.sender, amount);
            totalDeposits = totalDeposits.sub(depositTokenAmount);
            emit Withdraw(msg.sender, depositTokenAmount);
        }
    }

    function _withdrawDepositTokens(uint256 amount) private {
        require(amount > 0, "CurveStrategyForAv3CRVV1::_withdrawDepositTokens");
        stakingContract.withdraw(amount);
    }

    function reinvest() external override onlyEOA {
        (uint256 avaxAmount, uint256 crvAmount) = _claimRewards();
        uint256 unclaimedRewards = _estimateRewardConvertedToAvax(avaxAmount, crvAmount);
        require(unclaimedRewards >= MIN_TOKENS_TO_REINVEST, "CurveStrategyForAv3CRVV1::reinvest");
        _reinvest(avaxAmount, crvAmount);
    }

    function _claimRewards() private returns (uint256 _avaxAmount, uint256 _crvAmount) {
        ICurveRewardsClaimer(stakingContract.reward_contract()).get_reward();
        stakingContract.claim_rewards();
        uint256 avaxAmount = IERC20(WAVAX).balanceOf(address(this));
        uint256 crvAmount = IERC20(CRV).balanceOf(address(this));
        return (avaxAmount, crvAmount);
    }

    function _estimateRewardConvertedToAvax(uint256 avaxAmount, uint256 crvAmount) private view returns (uint256) {
        uint256 estimatedWAVAX = 0;
        if (swapPairCrvAvax > address(0)) {
            estimatedWAVAX = DexLibrary.estimateConversionThroughPair(
                crvAmount,
                address(CRV),
                address(WAVAX),
                IPair(swapPairCrvAvax)
            );
        }
        return avaxAmount.add(estimatedWAVAX);
    }

    /**
     * @notice Reinvest rewards from staking contract to deposit tokens
     * @dev Reverts if the expected amount of tokens are not returned from `stableSwap`
     */
    function _reinvest(uint256 avaxAmount, uint256 crvAmount) private {
        uint256 amount = avaxAmount.add(_convertRewardIntoWAVAX(crvAmount));

        uint256 devFee = amount.mul(DEV_FEE_BIPS).div(BIPS_DIVISOR);
        if (devFee > 0) {
            _safeTransfer(address(rewardToken), devAddr, devFee);
        }

        uint256 adminFee = amount.mul(ADMIN_FEE_BIPS).div(BIPS_DIVISOR);
        if (adminFee > 0) {
            _safeTransfer(address(rewardToken), owner(), adminFee);
        }

        uint256 reinvestFee = amount.mul(REINVEST_REWARD_BIPS).div(BIPS_DIVISOR);
        if (reinvestFee > 0) {
            _safeTransfer(address(rewardToken), msg.sender, reinvestFee);
        }

        uint256 depositTokenAmount = _zapToDepositToken(amount.sub(devFee).sub(adminFee).sub(reinvestFee));

        _stakeDepositTokens(depositTokenAmount);
        totalDeposits = totalDeposits.add(depositTokenAmount);

        emit Reinvest(totalDeposits, totalSupply);
    }

    function _convertRewardIntoWAVAX(uint256 crvAmount) private returns (uint256) {
        if (swapPairCrvAvax > address(0)) {
            return DexLibrary.swap(crvAmount, address(CRV), address(WAVAX), IPair(swapPairCrvAvax));
        }
        return 0;
    }

    function _stakeDepositTokens(uint256 amount) private {
        require(amount > 0, "CurveStrategyForAv3CRVV1::_stakeDepositTokens");
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
        require(IERC20(token).transfer(to, value), "CurveStrategyForAv3CRVV1::TRANSFER_FROM_FAILED");
    }

    function checkReward() public view override returns (uint256) {
        uint256 pendingAvaxRewards = _calculateRewards(WAVAX);
        uint256 pendingCrvRewards = _calculateRewards(CRV);

        return _estimateRewardConvertedToAvax(pendingAvaxRewards, pendingCrvRewards);
    }

    function _calculateRewards(address _rewardToken) public view returns (uint256) {
        uint256 strategyLpDeposits = stakingContract.balanceOf(address(this));
        uint256 lastRewardUpdateTime = ICurveRewardsClaimer(stakingContract.reward_contract()).last_update_time();
        DataTypes.RewardToken memory rewardToken = ICurveRewardsClaimer(stakingContract.reward_contract()).reward_data(
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
            strategyUnclaimed = strategyLpDeposits.mul(integral.sub(integralFor)).div(10e18);
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
            "CurveStrategyForAv3CRVV1::rescueDeployedFunds"
        );
        totalDeposits = balanceAfter;
        emit Reinvest(totalDeposits, totalSupply);
        if (DEPOSITS_ENABLED == true && disableDeposits == true) {
            updateDepositsEnabled(false);
        }
    }
}
