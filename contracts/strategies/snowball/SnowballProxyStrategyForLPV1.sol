// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../YakStrategyV2.sol";
import "./interfaces/ISnowGlobe.sol";
import "./interfaces/IGauge.sol";
import "../../interfaces/IPair.sol";
import "./interfaces/ISnowballProxy.sol";
import "../../lib/DexLibrary.sol";
import "../../lib/SafeERC20.sol";

/**
 * @notice Snowball strategy
 */
contract SnowballProxyStrategyForLPV1 is YakStrategyV2 {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    address public immutable stakingContract;
    address public immutable snowGlobe;
    IPair private swapPairWAVAXSnob;
    IPair private swapPairToken0;
    IPair private swapPairToken1;
    IWAVAX private constant WAVAX = IWAVAX(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);
    ISnowballProxy private proxy;

    constructor (
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
        StrategySettings memory _strategySettings
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
        applyStrategySettings(_strategySettings);
        updateDepositsEnabled(true);
        transferOwnership(_timelock);

        emit Reinvest(0, 0);
    }

    /**
     * @notice Initialization helper for Pair deposit tokens
     * @dev Checks that selected Pairs are valid for trading reward tokens
     * @dev Assigns values to swapPairToken0 and swapPairToken1
     */
    function assignSwapPairSafely(address _swapPairWAVAXSnob, address _swapPairToken0, address _swapPairToken1, address _rewardToken) private {
        require(
            DexLibrary.checkSwapPairCompatibility(IPair(_swapPairWAVAXSnob), address(WAVAX), address(_rewardToken)),
            "_swapPairWAVAXSnob is not a WAVAX-Snob pair"
        );
        require(
            _swapPairToken0 == address(0)
            || DexLibrary.checkSwapPairCompatibility(IPair(_swapPairToken0), address(WAVAX), IPair(address(depositToken)).token0()),
            "_swapPairToken0 is not a WAVAX+deposit token0"
        );
        require(
            _swapPairToken1 == address(0)
            || DexLibrary.checkSwapPairCompatibility(IPair(_swapPairToken1), address(WAVAX), IPair(address(depositToken)).token1()),
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

    function deposit(uint amount) external override {
        _deposit(msg.sender, amount);
    }

    function depositWithPermit(uint amount, uint deadline, uint8 v, bytes32 r, bytes32 s) external override {
        depositToken.permit(msg.sender, address(this), amount, deadline, v, r, s);
        _deposit(msg.sender, amount);
    }

    function depositFor(address account, uint amount) external override {
        _deposit(account, amount);
    }

    function _deposit(address account, uint amount) private onlyAllowedDeposits {
        require(DEPOSITS_ENABLED == true, "SnowballStrategyForLPV1::_deposit");
        if (MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST > 0) {
            uint unclaimedRewards = checkReward();
            if (unclaimedRewards > MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST) {
                _reinvest(_convertRewardIntoWAVAX(unclaimedRewards));
            }
        }
        _stakeDepositTokens(msg.sender, amount);
        _mint(account, getSharesForDepositTokens(amount));
        emit Deposit(account, amount);
    }

    function _stakeDepositTokens(address from, uint amount) private {
        require(amount > 0, "SnowballStrategyForLPV1::_stakeDepositTokens");
        require(depositToken.transferFrom(from, address(proxy), amount), "SnowballStrategyForLPV1::_stakeDepositTokens transfer failed");
        proxy.deposit(stakingContract, snowGlobe, address(depositToken));
    }

    function withdraw(uint amount) external override {
        uint depositTokenAmount = getDepositTokensForShares(amount);
        if (depositTokenAmount > 0) {
            uint amountReceived = _withdrawDepositTokens(depositTokenAmount);
            IERC20(address(depositToken)).safeTransfer(msg.sender, amountReceived);
            _burn(msg.sender, amount);
            emit Withdraw(msg.sender, depositTokenAmount);
        }
    }

    function _withdrawDepositTokens(uint amount) private returns (uint) {
        require(amount > 0, "SnowballStrategyForLPV1::_withdrawDepositTokens");
        return proxy.withdraw(stakingContract, snowGlobe, address(depositToken), amount);
    }

    function reinvest() external override onlyEOA {
        uint unclaimedRewards = proxy.checkReward(stakingContract);
        require(unclaimedRewards >= MIN_TOKENS_TO_REINVEST, "SnowballStrategyForLPV1::reinvest");
        _reinvest(_convertRewardIntoWAVAX(unclaimedRewards));
    }

    function _convertRewardIntoWAVAX(uint pendingReward) private returns (uint) {
        proxy.claimReward(stakingContract);
        return DexLibrary.swap(
            pendingReward,
            address(rewardToken), address(WAVAX),
            swapPairWAVAXSnob
        );
    }

    /**
     * @notice Reinvest rewards from staking contract to deposit tokens
     * @dev Reverts if the expected amount of tokens are not returned from `stakingContract`
     * @param amount deposit tokens to reinvest
     */
    function _reinvest(uint amount) private {
        uint devFee = amount.mul(DEV_FEE_BIPS).div(BIPS_DIVISOR);
        if (devFee > 0) {
            IERC20(address(WAVAX)).safeTransfer(devAddr, devFee);
        }

        uint adminFee = amount.mul(ADMIN_FEE_BIPS).div(BIPS_DIVISOR);
        if (adminFee > 0) {
            IERC20(address(WAVAX)).safeTransfer(owner(), adminFee);
        }

        uint reinvestFee = amount.mul(REINVEST_REWARD_BIPS).div(BIPS_DIVISOR);
        if (reinvestFee > 0) {
            IERC20(address(WAVAX)).safeTransfer(msg.sender, reinvestFee);
        }

        uint depositTokenAmount = DexLibrary.convertRewardTokensToDepositTokens(
            amount.sub(devFee).sub(adminFee).sub(reinvestFee),
            address(WAVAX),
            address(depositToken),
            swapPairToken0,
            swapPairToken1
        );

        _stakeDepositTokens(address(this), depositTokenAmount);

        emit Reinvest(totalDeposits(), totalSupply);
    }
    
    function checkReward() public override view returns (uint) {
        uint pendingReward = proxy.checkReward(stakingContract);
        return DexLibrary.estimateConversionThroughPair(
            pendingReward,
            address(rewardToken), address(WAVAX),
            swapPairWAVAXSnob
        );
    }

    function estimateDeployedBalance() external override view returns (uint) {
        return proxy.balanceOf(stakingContract, snowGlobe);
    }

    function totalDeposits() public override view returns (uint) {
        return proxy.balanceOf(stakingContract, snowGlobe);
    }

    function rescueDeployedFunds(uint minReturnAmountAccepted, bool disableDeposits) external override onlyOwner {
        uint balanceBefore = depositToken.balanceOf(address(this));
        proxy.withdrawAll(stakingContract, snowGlobe, address(depositToken));
        uint balanceAfter = depositToken.balanceOf(address(this));
        require(balanceAfter.sub(balanceBefore) >= minReturnAmountAccepted, "SnowballStrategyForLPV1::rescueDeployedFunds");
        emit Reinvest(totalDeposits(), totalSupply);
        if (DEPOSITS_ENABLED == true && disableDeposits == true) {
            updateDepositsEnabled(false);
        }
    }
}