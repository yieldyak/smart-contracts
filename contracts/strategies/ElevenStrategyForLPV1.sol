// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "../YakStrategyV2.sol";
import "../interfaces/IElevenChef.sol";
import "../interfaces/IElevenGrowthVault.sol";
import "../interfaces/IElevenQuickStrat.sol";
import "../interfaces/IPair.sol";
import "../lib/DexLibrary.sol";

/**
 * @notice Strategy for CycleVaults
 */
contract ElevenStrategyForLPV1 is YakStrategyV2 {
    using SafeMath for uint;

    IElevenChef public stakingContract;
    IElevenGrowthVault public vaultContract;
    IPair private immutable swapPairToken0;
    IPair private immutable swapPairToken1;
    IPair private immutable swapPairWAVAXELE;
    uint private immutable PID;
    address private constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;

    constructor (
        string memory _name,
        address _depositToken,
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
        rewardToken = IERC20(_rewardToken);
        stakingContract = IElevenChef(_stakingContract);
        vaultContract = IElevenGrowthVault(_vaultContract);
        PID = _pid;
        devAddr = msg.sender;

        require(
            DexLibrary.checkSwapPairCompatibility(IPair(_swapPairWAVAXELE), address(WAVAX), address(rewardToken)),
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
        transferOwnership(_timelock);

        emit Reinvest(0, 0);
    }


    function totalDeposits() public override view returns (uint) {
        return deployedLPBalance();
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
        require(DEPOSITS_ENABLED == true, "ElevenStrategyV1::_deposit");
        if (MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST > 0) {
            uint unclaimedRewards = checkReward();
            if (unclaimedRewards > MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST) {
                _reinvest(unclaimedRewards);
            }
        }
        require(depositToken.transferFrom(msg.sender, address(this), amount), "ElevenStrategyV1::transfer failed");
        _mint(account, getSharesForDepositTokens(amount));
        _stakeDepositTokens(amount);
        emit Deposit(account, amount);
    }

    function withdraw(uint amount) external override {
        require(amount > 0, "ElevenStrategyV1::withdraw");
        uint depositTokenAmount = _convertSharesToDepositTokens(amount);
        uint elevenShares = _convertSharesToElevenShares(amount);
        stakingContract.withdraw(PID, elevenShares);
        vaultContract.withdraw(elevenShares);
        _safeTransfer(address(depositToken), msg.sender, depositTokenAmount);
        _burn(msg.sender, amount);
        emit Withdraw(msg.sender, depositTokenAmount);
    }
    
    function _convertSharesToDepositTokens(uint amount) public view returns (uint) {
        uint lpAmount = getDepositTokensForShares(amount);
        uint withdrawalFee = _calculateWithdrawalFee(lpAmount);
        return lpAmount.sub(withdrawalFee);
    }

    function _convertSharesToElevenShares(uint amount) private returns (uint) {
        (uint elevenShareBalance, ) = stakingContract.userInfo(PID, address(this));
        return amount.mul(elevenShareBalance).div(totalSupply);
    }

    function reinvest() external override onlyEOA {
        uint unclaimedRewards = _checkReward();
        require(unclaimedRewards >= MIN_TOKENS_TO_REINVEST, "ElevenStrategyV1::reinvest");
        _reinvest(unclaimedRewards);
    }

    /**
     * @notice Reinvest rewards from staking contract to deposit tokens
     * @dev Reverts if the expected amount of tokens are not returned from `stakingContract`
     * @param amount deposit tokens to reinvest
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
            address(rewardToken), address(WAVAX),
            swapPairWAVAXELE
        );
    }
    
    function _stakeDepositTokens(uint amount) private {
        require(amount > 0, "ElevenStrategyV1::_stakeDepositTokens");
        vaultContract.deposit(amount);
        uint elevenShares = vaultContract.balanceOf(address(this));
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
        require(IERC20(token).transfer(to, value), 'ElevenStrategyV1::TRANSFER_FROM_FAILED');
    }

    function _checkReward() private view returns (uint) {
        return stakingContract.pendingEleven(PID, address(this));
    }

    function checkReward() public override view returns (uint) {
        uint pendingReward = _checkReward();
        return DexLibrary.estimateConversionThroughPair(
            pendingReward,
            address(rewardToken), address(WAVAX),
            swapPairWAVAXELE
        );
    }

    function deployedLPBalance() private view returns (uint) {
        (uint sharesAmount, ) = stakingContract.userInfo(PID, address(this));
        uint totalLPDeposits = vaultContract.balance();
        uint sharesTotalSupply = vaultContract.totalSupply();
        return sharesAmount.mul(totalLPDeposits).div(sharesTotalSupply);
    }

    function _calculateWithdrawalFee(uint _withdrawalAmount) private view returns (uint) {
        return _withdrawalAmount
            .mul(IElevenQuickStrat(vaultContract.strategy()).WITHDRAWAL_FEE())
            .div(IElevenQuickStrat(vaultContract.strategy()).WITHDRAWAL_MAX());
    }

    function estimateDeployedBalance() external override view returns (uint) {
        uint deployedLP = deployedLPBalance();
        uint withdrawalFee = _calculateWithdrawalFee(deployedLP);
        return deployedLP.sub(withdrawalFee);
    }

    function rescueDeployedFunds(uint minReturnAmountAccepted, bool disableDeposits) external override onlyOwner {
        uint balanceBefore = depositToken.balanceOf(address(this));
        stakingContract.emergencyWithdraw(PID);
        vaultContract.withdrawAll();
        uint balanceAfter = depositToken.balanceOf(address(this));
        require(balanceAfter.sub(balanceBefore) >= minReturnAmountAccepted, "ElevenStrategyV1::rescueDeployedFunds");
        emit Reinvest(totalDeposits(), totalSupply);
        if (DEPOSITS_ENABLED == true && disableDeposits == true) {
            updateDepositsEnabled(false);
        }
    }
}