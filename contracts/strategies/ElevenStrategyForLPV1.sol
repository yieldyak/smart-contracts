// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

import "../YakStrategyV2.sol";
import "../interfaces/IElevenChef.sol";
import "../interfaces/IElevenGrowthVault.sol";
import "../interfaces/IElevenQuickStrat.sol";
import "../interfaces/IPair.sol";
import "../lib/DexLibrary.sol";

/**
 * @notice Strategy for ElevenVaults
 */
contract ElevenStrategyForLPV1 is YakStrategyV2 {
    using SafeMath for uint;

    IElevenChef public stakingContract;
    IElevenGrowthVault public vaultContract;
    IPair private immutable swapPairToken0;
    IPair private immutable swapPairToken1;
    IPair private immutable swapPairWAVAXELE;
    uint public immutable PID;
    address private constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    IERC20 private immutable poolRewardToken;

    constructor (
        string memory _name,
        address _depositToken,
        address _poolRewardToken,
        address _rewardToken,
        address _stakingContract,
        address _vaultContract,
        address _swapPairWAVAXELE,
        address _swapPairToken0,
        address _swapPairToken1,
        address _timelock,
        uint _pid,
        uint _minTokensToReinvest,
        uint _adminFeeBips,
        uint _devFeeBips,
        uint _reinvestRewardBips
    ) {
        name = _name;
        depositToken = IERC20(_depositToken);
        poolRewardToken = IERC20(_poolRewardToken);
        rewardToken = IERC20(_rewardToken);
        stakingContract = IElevenChef(_stakingContract);
        vaultContract = IElevenGrowthVault(_vaultContract);
        PID = _pid;
        devAddr = msg.sender;

        require(
            DexLibrary.checkSwapPairCompatibility(IPair(_swapPairWAVAXELE), address(WAVAX), _poolRewardToken),
            "_swapPairWAVAXELE is not a WAVAX-ELE pair"
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
        swapPairWAVAXELE = IPair(_swapPairWAVAXELE);
        swapPairToken0 = IPair(_swapPairToken0);
        swapPairToken1 = IPair(_swapPairToken1);

        setAllowances();
        updateMinTokensToReinvest(_minTokensToReinvest);
        updateAdminFee(_adminFeeBips);
        updateDevFee(_devFeeBips);
        updateReinvestReward(_reinvestRewardBips);
        updateDepositsEnabled(true);
        // transferOwnership(_timelock);

        emit Reinvest(0, 0);
    }

    function setAllowances() public override onlyOwner {
        depositToken.approve(address(vaultContract), type(uint256).max);
        IERC20(address(vaultContract)).approve(address(stakingContract), type(uint256).max);
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
        require(DEPOSITS_ENABLED == true, "ElevenStrategyForLPV1::_deposit");
        if (MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST > 0) {
            (uint poolTokenAmount, uint unclaimedRewards) = _checkReward();
            if (unclaimedRewards > MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST) {
                _reinvest(poolTokenAmount);
            }
        }
        require(depositToken.transferFrom(msg.sender, address(this), amount), "ElevenStrategyForLPV1::transfer failed");
        _mint(account, getSharesForDepositTokens(amount));
        _stakeDepositTokens(amount);
        emit Deposit(account, amount);
    }

    function withdraw(uint amount) external override {
        uint elevenShares = _convertSharesToElevenShares(amount);
        uint depositTokenAmount = _convertElevenSharesToDepositTokens(elevenShares);
        require(depositTokenAmount > 0, "ElevenStrategyForLPV1::withdraw");
        stakingContract.withdraw(PID, elevenShares);
        vaultContract.withdraw(elevenShares);
        uint withdrawFee = _calculateWithdrawalFee(depositTokenAmount);
        _safeTransfer(address(depositToken), msg.sender, depositTokenAmount.sub(withdrawFee));
        _burn(msg.sender, amount);
        emit Withdraw(msg.sender, depositTokenAmount);
    }
    
    function _convertElevenSharesToDepositTokens(uint amount) private view returns (uint) {
        return amount.mul(vaultContract.balance()).div(vaultContract.totalSupply());
    }

    function _convertSharesToElevenShares(uint amount) private view returns (uint) {
        (uint elevenShareBalance, ) = stakingContract.userInfo(PID, address(this));
        return amount.mul(elevenShareBalance).div(totalSupply);
    }

    function reinvest() external override onlyEOA {
        (uint poolTokenAmount, uint unclaimedRewards) = _checkReward();
        require(unclaimedRewards >= MIN_TOKENS_TO_REINVEST, "ElevenStrategyForLPV1::reinvest");
        _reinvest(poolTokenAmount);
    }

    /**
     * @notice Reinvest rewards from staking contract to deposit tokens
     * @dev Reverts if the expected amount of tokens are not returned from `stakingContract`
     * @param amount pool reward tokens to reinvest
     */
    function _reinvest(uint amount) private {
        stakingContract.deposit(PID, 0);

        uint avaxAmount = _convertRewardIntoWAVAX(amount);

        uint devFee = avaxAmount.mul(DEV_FEE_BIPS).div(BIPS_DIVISOR);
        if (devFee > 0) {
            _safeTransfer(address(WAVAX), devAddr, devFee);
        }

        uint adminFee = avaxAmount.mul(ADMIN_FEE_BIPS).div(BIPS_DIVISOR);
        if (adminFee > 0) {
            _safeTransfer(address(WAVAX), owner(), adminFee);
        }

        uint reinvestFee = avaxAmount.mul(REINVEST_REWARD_BIPS).div(BIPS_DIVISOR);
        if (reinvestFee > 0) {
            _safeTransfer(address(WAVAX), msg.sender, reinvestFee);
        }

        uint depositTokenAmount = DexLibrary.convertRewardTokensToDepositTokens(
            avaxAmount.sub(devFee).sub(adminFee).sub(reinvestFee),
            address(WAVAX),
            address(depositToken),
            swapPairToken0,
            swapPairToken1
        );

        _stakeDepositTokens(depositTokenAmount);

        emit Reinvest(totalDeposits(), totalSupply);
    }

    function _convertRewardIntoWAVAX(uint pendingReward) private returns (uint) {
        return DexLibrary.swap(
            pendingReward,
            address(poolRewardToken), address(WAVAX),
            swapPairWAVAXELE
        );
    }
    
    function _stakeDepositTokens(uint amount) private {
        require(amount > 0, "ElevenStrategyForLPV1::_stakeDepositTokens");
        uint elevenShares = amount.mul(vaultContract.totalSupply()).div(vaultContract.balance());
        vaultContract.deposit(amount);
        stakingContract.deposit(PID, elevenShares);
    }

    /**
     * @notice Safely transfer using an anonymous ERC20 token
     * @dev Requires token to return true on transfer
     * @param token address
     * @param to recipient address
     * @param value amount
     */
    function _safeTransfer(address token, address to, uint256 value) private {
        require(IERC20(token).transfer(to, value), "ElevenStrategyForLPV1::TRANSFER_FROM_FAILED");
    }

    function _checkReward() private view returns (uint poolTokenAmount, uint rewardTokenAmount) {
        uint poolTokenAmount = stakingContract.pendingEleven(PID, address(this));
        uint poolTokenBalance = poolRewardToken.balanceOf(address(this));
        uint wavaxAmount = DexLibrary.estimateConversionThroughPair(
            poolTokenAmount.add(poolTokenBalance),
            address(poolRewardToken), address(WAVAX),
            swapPairWAVAXELE
        );
        uint wavaxBalance = IERC20(address(WAVAX)).balanceOf(address(this));
        return (poolTokenAmount.add(poolTokenBalance), wavaxAmount.add(wavaxBalance));
    }

    function checkReward() public override view returns (uint) {
        (,uint pendingReward) = _checkReward();
        return pendingReward;
    }

    function totalDeposits() public override view returns (uint) {
        (uint sharesAmount, ) = stakingContract.userInfo(PID, address(this));
        return _convertElevenSharesToDepositTokens(sharesAmount);
    }

    function _calculateWithdrawalFee(uint _withdrawalAmount) private view returns (uint) {
        return _withdrawalAmount
            .mul(IElevenQuickStrat(vaultContract.strategy()).WITHDRAWAL_FEE())
            .div(IElevenQuickStrat(vaultContract.strategy()).WITHDRAWAL_MAX());
    }

    function estimateDeployedBalance() external override view returns (uint) {
        uint deployedLP = totalDeposits();
        uint withdrawalFee = _calculateWithdrawalFee(deployedLP);
        return deployedLP.sub(withdrawalFee);
    }

    function rescueDeployedFunds(uint minReturnAmountAccepted, bool disableDeposits) external override onlyOwner {
        uint balanceBefore = depositToken.balanceOf(address(this));
        stakingContract.emergencyWithdraw(PID);
        vaultContract.withdrawAll();
        uint balanceAfter = depositToken.balanceOf(address(this));
        require(balanceAfter.sub(balanceBefore) >= minReturnAmountAccepted, "ElevenStrategyForLPV1::rescueDeployedFunds");
        emit Reinvest(totalDeposits(), totalSupply);
        if (DEPOSITS_ENABLED == true && disableDeposits == true) {
            updateDepositsEnabled(false);
        }
    }
}