// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "../YakStrategy.sol";
import "../interfaces/ISnowGlobe.sol";
import "../interfaces/IGauge.sol";
import "../interfaces/IPair.sol";
import "../lib/DexLibrary.sol";
import "../interfaces/IJoeBar.sol";

/**
 * @notice Snowball strategy
 */
contract SnowballStrategyForSAV1 is YakStrategy {
    using SafeMath for uint;

    IGauge public stakingContract;
    ISnowGlobe public snowGlobe;
    IJoeBar public joeBar;
    IPair private swapPairWAVAXSnob;
    IPair private swapPairDepositToken;
    IPair private swapPairToken1;
    function(uint) internal returns(uint) swapToDepositToken;
    IWAVAX private constant WAVAX = IWAVAX(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);

    constructor (
        string memory _name,
        address _depositToken,
        address _rewardToken,
        address _stakingContract,
        address _snowGlobeContract,
        address _swapPairWAVAXSnob,
        address _swapPairDepositToken,
        address _joeBar,
        address _timelock,
        uint _minTokensToReinvest,
        uint _adminFeeBips,
        uint _devFeeBips,
        uint _reinvestRewardBips
    ) {
        name = _name;
        depositToken = IERC20(_depositToken);
        rewardToken = IERC20(_rewardToken);
        stakingContract = IGauge(_stakingContract);
        snowGlobe = ISnowGlobe(_snowGlobeContract);

        if (_joeBar != address(0)) {
            joeBar = IJoeBar(_joeBar);
            swapToDepositToken = _swapAndConvertToXJoe;
        } else {
            swapToDepositToken = _onlySwap;
        }

        devAddr = msg.sender;

        assignSwapPairSafely(_swapPairWAVAXSnob, _swapPairDepositToken, _rewardToken, _depositToken);
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
     * @dev Assigns values to swapPairWAVAXSnob and swapPairDepositToken
     */
    function assignSwapPairSafely(address _swapPairWAVAXSnob, address _swapPairDepositToken, address _rewardToken, address _depositToken) private {
        require(
            DexLibrary.checkSwapPairCompatibility(IPair(_swapPairWAVAXSnob), address(WAVAX), _rewardToken),
            "_swapPairWAVAXSnob is not a WAVAX-Snob pair"
        );
        require(
            DexLibrary.checkSwapPairCompatibility(IPair(_swapPairDepositToken), address(WAVAX), _depositToken),
            "_swapPairDepositToken is not a WAVAX-DepositToken pair"
        );
        // converts Snob to WAVAX
        swapPairWAVAXSnob = IPair(_swapPairWAVAXSnob);
        // converts WAVAX to Deposit Token
        swapPairDepositToken = IPair(_swapPairDepositToken);
    }

    function setAllowances() public override onlyOwner {
        depositToken.approve(address(snowGlobe), MAX_UINT);
        snowGlobe.approve(address(stakingContract), MAX_UINT);
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
        require(DEPOSITS_ENABLED == true, "SnowballStrategyForSAV1::_deposit");
        if (MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST > 0) {
            uint unclaimedRewards = checkReward();
            if (unclaimedRewards > MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST) {
                _reinvest(unclaimedRewards);
            }
        }
        require(depositToken.transferFrom(msg.sender, address(this), amount));
        uint lpAmountDeposited = _stakeDepositTokens(amount);
        _mint(account, getSharesForDepositTokens(lpAmountDeposited));
        totalDeposits = totalDeposits.add(lpAmountDeposited);
        emit Deposit(account, lpAmountDeposited);
    }

    function _stakeDepositTokens(uint amount) private returns (uint) {
        require(amount > 0, "SnowballStrategyForSAV1::_stakeDepositTokens");
        snowGlobe.deposit(amount);
        uint snowballSharesAmount = snowGlobe.balanceOf(address(this));
        uint lpAmountDeposited = snowballSharesAmount.mul(snowGlobe.getRatio()).div(1e18);
        stakingContract.deposit(snowballSharesAmount);
        return lpAmountDeposited;
    }

    function withdraw(uint amount) external override {
        uint depositTokenAmount = getDepositTokensForShares(amount);
        if (depositTokenAmount > 0) {
            _withdrawDepositTokens(depositTokenAmount);
            _safeTransfer(address(depositToken), msg.sender, amount);
            _burn(msg.sender, amount);
            totalDeposits = totalDeposits.sub(depositTokenAmount);
            emit Withdraw(msg.sender, depositTokenAmount);
        }
    }

    function _withdrawDepositTokens(uint amount) private {
        require(amount > 0, "SnowballStrategyForSAV1::_withdrawDepositTokens");
        uint sharesAmount = amount.mul(1e18).div(snowGlobe.getRatio());
        stakingContract.withdraw(sharesAmount);
        snowGlobe.withdraw(sharesAmount);
    }

    function reinvest() external override onlyEOA {
        uint unclaimedRewards = checkReward();
        require(unclaimedRewards >= MIN_TOKENS_TO_REINVEST, "SnowballStrategyForSAV1::reinvest");
        _reinvest(_convertRewardIntoWAVAX(unclaimedRewards));
    }

    function _convertRewardIntoWAVAX(uint pendingReward) private returns (uint) {
        stakingContract.getReward();
        DexLibrary.swap(
            pendingReward,
            address(rewardToken), address(WAVAX),
            swapPairWAVAXSnob
        );
        return WAVAX.balanceOf(address(this));
    }

    /**
     * @notice Reinvest rewards from staking contract to deposit tokens
     * @dev Reverts if the expected amount of tokens are not returned from `stakingContract`
     * @param amount deposit tokens to reinvest
     */
    function _reinvest(uint amount) private {
        uint devFee = amount.mul(DEV_FEE_BIPS).div(BIPS_DIVISOR);
        if (devFee > 0) {
            _safeTransfer(address(WAVAX), devAddr, devFee);
        }

        uint adminFee = amount.mul(ADMIN_FEE_BIPS).div(BIPS_DIVISOR);
        if (adminFee > 0) {
            _safeTransfer(address(WAVAX), owner(), adminFee);
        }

        uint reinvestFee = amount.mul(REINVEST_REWARD_BIPS).div(BIPS_DIVISOR);
        if (reinvestFee > 0) {
            _safeTransfer(address(WAVAX), msg.sender, reinvestFee);
        }

        uint depositTokenAmount = swapToDepositToken(amount.sub(devFee).sub(adminFee).sub(reinvestFee));

        _stakeDepositTokens(depositTokenAmount);
        totalDeposits = totalDeposits.add(depositTokenAmount);

        emit Reinvest(totalDeposits, totalSupply);
    }


    function _onlySwap(uint amount) private returns (uint) {
        return DexLibrary.swap(
            amount,
            address(WAVAX),
            address(depositToken),
            swapPairDepositToken
        );
    }

    function _swapAndConvertToXJoe(uint amount) private returns (uint) {
        uint joeAmount = DexLibrary.swap(
            amount,
            address(WAVAX),
            address(depositToken),
            swapPairDepositToken
        );
        joeBar.enter(amount);
        return joeBar.balanceOf(address(this));
    }

    /**
     * @notice Safely transfer using an anonymosu ERC20 token
     * @dev Requires token to return true on transfer
     * @param token address
     * @param to recipient address
     * @param value amount
     */
    function _safeTransfer(address token, address to, uint256 value) private {
        require(IERC20(token).transfer(to, value), 'SnowballStrategyForSAV1::_safeTransfer');
    }

    function checkReward() public override view returns (uint) {
        uint unclaimedReward = stakingContract.earned(address(this));
        uint pendingReward = unclaimedReward.add(rewardToken.balanceOf(address(this)));
        return DexLibrary.estimateConversionThroughPair(
            pendingReward,
            address(rewardToken), address(WAVAX),
            swapPairWAVAXSnob
        );
    }

    function estimateDeployedBalance() external override view returns (uint) {
        return stakingContract.balanceOf(address(this));
    }

    function rescueDeployedFunds(uint minReturnAmountAccepted, bool disableDeposits) external override onlyOwner {
        uint balanceBefore = depositToken.balanceOf(address(this));
        stakingContract.withdrawAll();
        snowGlobe.withdrawAll();
        stakingContract.withdraw(stakingContract.balanceOf(address(this)));
        uint balanceAfter = depositToken.balanceOf(address(this));
        require(balanceAfter.sub(balanceBefore) >= minReturnAmountAccepted, "SnowballStrategyForSAV1::rescueDeployedFunds");
        totalDeposits = balanceAfter;
        emit Reinvest(totalDeposits, totalSupply);
        if (DEPOSITS_ENABLED == true && disableDeposits == true) {
            updateDepositsEnabled(false);
        }
    }
}