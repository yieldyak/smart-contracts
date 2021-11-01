// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "../YakStrategy.sol";
import "../interfaces/IStakingRewards.sol";
import "../interfaces/IPair.sol";
import "../lib/DexLibrary.sol";

/**
 * @notice Pool1 strategy for StakingRewards
 * @dev Converts pool reward tokens to WAVAX before compounding
 */
contract DexStrategyV6a is YakStrategy {
    using SafeMath for uint256;

    IStakingRewards public stakingContract;
    IPair private swapPairWavaxPoolReward;
    IPair private swapPairToken0;
    IPair private swapPairToken1;
    address private constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    IERC20 private immutable poolRewardToken;

    constructor(
        string memory _name,
        address _depositToken,
        address _stakingContract,
        address _poolRewardToken,
        address _swapPairWavaxPoolReward,
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
        rewardToken = IERC20(WAVAX);
        poolRewardToken = IERC20(_poolRewardToken);
        stakingContract = IStakingRewards(_stakingContract);
        devAddr = msg.sender;

        swapPairWavaxPoolReward = IPair(_swapPairWavaxPoolReward);
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

    function setAllowances() public override onlyOwner {
        depositToken.approve(address(stakingContract), MAX_UINT);
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
        require(DEPOSITS_ENABLED == true, "DexStrategyV6::_deposit");
        if (MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST > 0) {
            (uint256 poolRewardTokens, uint256 unclaimedRewards) = _checkReward();
            if (unclaimedRewards > MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST) {
                _reinvest(poolRewardTokens);
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
        require(amount > 0, "DexStrategyV6::_withdrawDepositTokens");
        stakingContract.withdraw(amount);
    }

    function reinvest() external override onlyEOA {
        (uint256 poolRewardTokens, uint256 unclaimedRewards) = _checkReward();
        require(unclaimedRewards >= MIN_TOKENS_TO_REINVEST, "DexStrategyV6::reinvest");
        _reinvest(poolRewardTokens);
    }

    /**
     * @notice Reinvest rewards from staking contract to deposit tokens
     * @dev Reverts if the expected amount is not returned from `stakingContract`
     * @param poolRewardTokens pool reward tokens to reinvest
     */
    function _reinvest(uint256 poolRewardTokens) private {
        stakingContract.getReward();

        uint256 amount = poolRewardTokens;
        if (address(swapPairWavaxPoolReward) != address(0)) {
            amount = DexLibrary.swap(
                poolRewardTokens,
                address(poolRewardToken),
                address(rewardToken),
                swapPairWavaxPoolReward
            );
        }

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

        uint256 depositTokenAmount = DexLibrary.convertRewardTokensToDepositTokens(
            amount.sub(devFee).sub(adminFee).sub(reinvestFee),
            address(rewardToken),
            address(depositToken),
            swapPairToken0,
            swapPairToken1
        );

        _stakeDepositTokens(depositTokenAmount);
        totalDeposits = totalDeposits.add(depositTokenAmount);

        emit Reinvest(totalDeposits, totalSupply);
    }

    function _stakeDepositTokens(uint256 amount) private {
        require(amount > 0, "DexStrategyV6::_stakeDepositTokens");
        stakingContract.stake(amount);
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
        require(IERC20(token).transfer(to, value), "DexStrategyV6::TRANSFER_FROM_FAILED");
    }

    function _checkReward() private view returns (uint256 poolRewardTokens, uint256 rewardTokens) {
        uint256 poolRewardTokens = stakingContract.earned(address(this));
        uint256 rewardTokens = poolRewardTokens;
        if (address(swapPairWavaxPoolReward) != address(0)) {
            rewardTokens = DexLibrary.estimateConversionThroughPair(
                poolRewardTokens,
                address(poolRewardToken),
                address(rewardToken),
                swapPairWavaxPoolReward
            );
        }
        return (poolRewardTokens, rewardTokens);
    }

    function checkReward() public view override returns (uint256) {
        (, uint256 unclaimedRewards) = _checkReward();
        return unclaimedRewards;
    }

    function estimateDeployedBalance() external view override returns (uint256) {
        return stakingContract.balanceOf(address(this));
    }

    function rescueDeployedFunds(uint256 minReturnAmountAccepted, bool disableDeposits) external override onlyOwner {
        uint256 balanceBefore = depositToken.balanceOf(address(this));
        stakingContract.exit();
        uint256 balanceAfter = depositToken.balanceOf(address(this));
        require(balanceAfter.sub(balanceBefore) >= minReturnAmountAccepted, "DexStrategyV6::rescueDeployedFunds");
        totalDeposits = balanceAfter;
        emit Reinvest(totalDeposits, totalSupply);
        if (DEPOSITS_ENABLED == true && disableDeposits == true) {
            updateDepositsEnabled(false);
        }
    }
}
