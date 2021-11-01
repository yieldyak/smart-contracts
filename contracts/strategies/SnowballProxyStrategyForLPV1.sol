// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "../YakStrategyV2.sol";
import "../interfaces/ISnowGlobe.sol";
import "../interfaces/IGauge.sol";
import "../interfaces/IPair.sol";
import "../interfaces/ISnowballProxy.sol";
import "../lib/DexLibrary.sol";

/**
 * @notice Snowball strategy
 */
contract SnowballProxyStrategyForLPV1 is YakStrategyV2 {
    using SafeMath for uint256;

    address public immutable stakingContract;
    address public immutable snowGlobe;
    IPair private swapPairWAVAXSnob;
    IPair private swapPairToken0;
    IPair private swapPairToken1;
    IWAVAX private constant WAVAX = IWAVAX(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);
    ISnowballProxy private proxy;

    constructor(
        string memory _name,
        address _depositToken,
        address _rewardToken,
        address _snowballProxy,
        address _stakingContract,
        address _snowGlobeContract,
        address _swapPairWAVAXSnob,
        address _swapPairToken0,
        address _swapPairToken1,
        address _timelock,
        uint256 _minTokensToReinvest,
        uint256 _adminFeeBips,
        uint256 _devFeeBips,
        uint256 _reinvestRewardBips
    ) {
        name = _name;
        depositToken = IERC20(_depositToken);
        rewardToken = IERC20(_rewardToken);
        proxy = ISnowballProxy(_snowballProxy);
        stakingContract = _stakingContract;
        snowGlobe = _snowGlobeContract;
        devAddr = msg.sender;

        assignSwapPairSafely(_swapPairWAVAXSnob, _swapPairToken0, _swapPairToken1, _rewardToken);
        setAllowances();
        updateMinTokensToReinvest(_minTokensToReinvest);
        updateAdminFee(_adminFeeBips);
        updateDevFee(_devFeeBips);
        updateReinvestReward(_reinvestRewardBips);
        updateDepositsEnabled(true);
        transferOwnership(_timelock);

        emit Reinvest(0, 0);
    }

    /**
     * @notice Initialization helper for Pair deposit tokens
     * @dev Checks that selected Pairs are valid for trading reward tokens
     * @dev Assigns values to swapPairToken0 and swapPairToken1
     */
    function assignSwapPairSafely(
        address _swapPairWAVAXSnob,
        address _swapPairToken0,
        address _swapPairToken1,
        address _rewardToken
    ) private {
        require(
            DexLibrary.checkSwapPairCompatibility(IPair(_swapPairWAVAXSnob), address(WAVAX), address(_rewardToken)),
            "_swapPairWAVAXSnob is not a WAVAX-Snob pair"
        );
        require(
            _swapPairToken0 == address(0) ||
                DexLibrary.checkSwapPairCompatibility(
                    IPair(_swapPairToken0),
                    address(WAVAX),
                    IPair(address(depositToken)).token0()
                ),
            "_swapPairToken0 is not a WAVAX+deposit token0"
        );
        require(
            _swapPairToken1 == address(0) ||
                DexLibrary.checkSwapPairCompatibility(
                    IPair(_swapPairToken1),
                    address(WAVAX),
                    IPair(address(depositToken)).token1()
                ),
            "_swapPairToken0 is not a WAVAX+deposit token1"
        );
        // converts Snob to WAVAX
        swapPairWAVAXSnob = IPair(_swapPairWAVAXSnob);
        // converts WAVAX to pair token0
        swapPairToken0 = IPair(_swapPairToken0);
        // converts WAVAX to pair token1
        swapPairToken1 = IPair(_swapPairToken1);
    }

    function setSnowballProxy(address _snowballProxy) external onlyOwner {
        proxy = ISnowballProxy(_snowballProxy);
    }

    function setAllowances() public override onlyOwner {
        depositToken.approve(address(this), MAX_UINT);
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
        require(DEPOSITS_ENABLED == true, "SnowballStrategyForLPV1::_deposit");
        if (MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST > 0) {
            uint256 unclaimedRewards = checkReward();
            if (unclaimedRewards > MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST) {
                _reinvest(_convertRewardIntoWAVAX(unclaimedRewards));
            }
        }
        _stakeDepositTokens(msg.sender, amount);
        _mint(account, getSharesForDepositTokens(amount));
        emit Deposit(account, amount);
    }

    function _stakeDepositTokens(address from, uint256 amount) private {
        require(amount > 0, "SnowballStrategyForLPV1::_stakeDepositTokens");
        require(
            depositToken.transferFrom(from, address(proxy), amount),
            "SnowballStrategyForLPV1::_stakeDepositTokens transfer failed"
        );
        proxy.deposit(stakingContract, snowGlobe, address(depositToken));
    }

    function withdraw(uint256 amount) external override {
        uint256 depositTokenAmount = getDepositTokensForShares(amount);
        if (depositTokenAmount > 0) {
            uint256 amountReceived = _withdrawDepositTokens(depositTokenAmount);
            _safeTransfer(address(depositToken), msg.sender, amountReceived);
            _burn(msg.sender, amount);
            emit Withdraw(msg.sender, depositTokenAmount);
        }
    }

    function _withdrawDepositTokens(uint256 amount) private returns (uint256) {
        require(amount > 0, "SnowballStrategyForLPV1::_withdrawDepositTokens");
        return proxy.withdraw(stakingContract, snowGlobe, address(depositToken), amount);
    }

    function reinvest() external override onlyEOA {
        uint256 unclaimedRewards = proxy.checkReward(stakingContract);
        require(unclaimedRewards >= MIN_TOKENS_TO_REINVEST, "SnowballStrategyForLPV1::reinvest");
        _reinvest(_convertRewardIntoWAVAX(unclaimedRewards));
    }

    function _convertRewardIntoWAVAX(uint256 pendingReward) private returns (uint256) {
        proxy.claimReward(stakingContract);
        return DexLibrary.swap(pendingReward, address(rewardToken), address(WAVAX), swapPairWAVAXSnob);
    }

    /**
     * @notice Reinvest rewards from staking contract to deposit tokens
     * @dev Reverts if the expected amount of tokens are not returned from `stakingContract`
     * @param amount deposit tokens to reinvest
     */
    function _reinvest(uint256 amount) private {
        uint256 devFee = amount.mul(DEV_FEE_BIPS).div(BIPS_DIVISOR);
        if (devFee > 0) {
            _safeTransfer(address(WAVAX), devAddr, devFee);
        }

        uint256 adminFee = amount.mul(ADMIN_FEE_BIPS).div(BIPS_DIVISOR);
        if (adminFee > 0) {
            _safeTransfer(address(WAVAX), owner(), adminFee);
        }

        uint256 reinvestFee = amount.mul(REINVEST_REWARD_BIPS).div(BIPS_DIVISOR);
        if (reinvestFee > 0) {
            _safeTransfer(address(WAVAX), msg.sender, reinvestFee);
        }

        uint256 depositTokenAmount = DexLibrary.convertRewardTokensToDepositTokens(
            amount.sub(devFee).sub(adminFee).sub(reinvestFee),
            address(WAVAX),
            address(depositToken),
            swapPairToken0,
            swapPairToken1
        );

        _stakeDepositTokens(address(this), depositTokenAmount);

        emit Reinvest(totalDeposits(), totalSupply);
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
        require(IERC20(token).transfer(to, value), "SnowballStrategyForLPV1::_safeTransfer");
    }

    function checkReward() public view override returns (uint256) {
        uint256 pendingReward = proxy.checkReward(stakingContract);
        return
            DexLibrary.estimateConversionThroughPair(
                pendingReward,
                address(rewardToken),
                address(WAVAX),
                swapPairWAVAXSnob
            );
    }

    function estimateDeployedBalance() external view override returns (uint256) {
        return proxy.balanceOf(stakingContract, snowGlobe);
    }

    function totalDeposits() public view override returns (uint256) {
        return proxy.balanceOf(stakingContract, snowGlobe);
    }

    function rescueDeployedFunds(uint256 minReturnAmountAccepted, bool disableDeposits) external override onlyOwner {
        uint256 balanceBefore = depositToken.balanceOf(address(this));
        proxy.withdrawAll(stakingContract, snowGlobe, address(depositToken));
        uint256 balanceAfter = depositToken.balanceOf(address(this));
        require(
            balanceAfter.sub(balanceBefore) >= minReturnAmountAccepted,
            "SnowballStrategyForLPV1::rescueDeployedFunds"
        );
        emit Reinvest(totalDeposits(), totalSupply);
        if (DEPOSITS_ENABLED == true && disableDeposits == true) {
            updateDepositsEnabled(false);
        }
    }
}
