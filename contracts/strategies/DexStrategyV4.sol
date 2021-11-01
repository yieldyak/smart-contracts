// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "../YakStrategy.sol";
import "../interfaces/IStakingRewards.sol";
import "../interfaces/IRouter.sol";
import "../interfaces/IPair.sol";

/**
 * @notice Pool2 strategy for StakingRewards
 */
contract DexStrategyV4 is YakStrategy {
    using SafeMath for uint256;

    IStakingRewards public stakingContract;
    IRouter public router;

    constructor(
        string memory _name,
        address _depositToken,
        address _rewardToken,
        address _stakingContract,
        address _router,
        address _timelock,
        uint256 _minTokensToReinvest,
        uint256 _adminFeeBips,
        uint256 _devFeeBips,
        uint256 _reinvestRewardBips
    ) {
        name = _name;
        depositToken = IERC20(_depositToken);
        rewardToken = IERC20(_rewardToken);
        stakingContract = IStakingRewards(_stakingContract);
        router = IRouter(_router);
        devAddr = msg.sender;

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
        rewardToken.approve(address(router), MAX_UINT);
        IERC20(IPair(address(depositToken)).token0()).approve(address(router), MAX_UINT);
        IERC20(IPair(address(depositToken)).token1()).approve(address(router), MAX_UINT);
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
        require(DEPOSITS_ENABLED == true, "DexStrategyV4::_deposit");
        if (MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST > 0) {
            uint256 unclaimedRewards = checkReward();
            if (unclaimedRewards > MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST) {
                _reinvest(unclaimedRewards);
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
            require(depositToken.transfer(msg.sender, depositTokenAmount), "DexStrategyV4::withdraw");
            _burn(msg.sender, amount);
            totalDeposits = totalDeposits.sub(depositTokenAmount);
            emit Withdraw(msg.sender, depositTokenAmount);
        }
    }

    function _withdrawDepositTokens(uint256 amount) private {
        require(amount > 0, "DexStrategyV4::_withdrawDepositTokens");
        stakingContract.withdraw(amount);
    }

    function reinvest() external override onlyEOA {
        uint256 unclaimedRewards = checkReward();
        require(unclaimedRewards >= MIN_TOKENS_TO_REINVEST, "DexStrategyV4::reinvest");
        _reinvest(unclaimedRewards);
    }

    /**
     * @notice Reinvest rewards from staking contract to deposit tokens
     * @dev Reverts if the expected amount of tokens are not returned from `stakingContract`
     * @param amount deposit tokens to reinvest
     */
    function _reinvest(uint256 amount) private {
        stakingContract.getReward();

        uint256 devFee = amount.mul(DEV_FEE_BIPS).div(BIPS_DIVISOR);
        if (devFee > 0) {
            require(rewardToken.transfer(devAddr, devFee), "DexStrategyV4::_reinvest, dev");
        }

        uint256 adminFee = amount.mul(ADMIN_FEE_BIPS).div(BIPS_DIVISOR);
        if (adminFee > 0) {
            require(rewardToken.transfer(owner(), adminFee), "DexStrategyV4::_reinvest, admin");
        }

        uint256 reinvestFee = amount.mul(REINVEST_REWARD_BIPS).div(BIPS_DIVISOR);
        if (reinvestFee > 0) {
            require(rewardToken.transfer(msg.sender, reinvestFee), "DexStrategyV4::_reinvest, reward");
        }

        uint256 depositTokenAmount = _convertRewardTokensToDepositTokens(
            amount.sub(devFee).sub(adminFee).sub(reinvestFee)
        );

        _stakeDepositTokens(depositTokenAmount);
        totalDeposits = totalDeposits.add(depositTokenAmount);

        emit Reinvest(totalDeposits, totalSupply);
    }

    function _stakeDepositTokens(uint256 amount) private {
        require(amount > 0, "DexStrategyV4::_stakeDepositTokens");
        stakingContract.stake(amount);
    }

    /**
     * @notice Converts reward tokens to deposit tokens
     * @dev Always converts through router; there are no price checks enabled
     * @return deposit tokens received
     */
    function _convertRewardTokensToDepositTokens(uint256 amount) private returns (uint256) {
        uint256 amountIn = amount.div(2);
        require(amountIn > 0, "DexStrategyV4::_convertRewardTokensToDepositTokens");

        // swap to token0
        uint256 path0Length = 2;
        address[] memory path0 = new address[](path0Length);
        path0[0] = address(rewardToken);
        path0[1] = IPair(address(depositToken)).token0();

        uint256 amountOutToken0 = amountIn;
        if (path0[0] != path0[path0Length - 1]) {
            uint256[] memory amountsOutToken0 = router.getAmountsOut(amountIn, path0);
            amountOutToken0 = amountsOutToken0[amountsOutToken0.length - 1];
            router.swapExactTokensForTokens(amountIn, amountOutToken0, path0, address(this), block.timestamp);
        }

        // swap to token1
        uint256 path1Length = 2;
        address[] memory path1 = new address[](path1Length);
        path1[0] = path0[0];
        path1[1] = IPair(address(depositToken)).token1();

        uint256 amountOutToken1 = amountIn;
        if (path1[0] != path1[path1Length - 1]) {
            uint256[] memory amountsOutToken1 = router.getAmountsOut(amountIn, path1);
            amountOutToken1 = amountsOutToken1[amountsOutToken1.length - 1];
            router.swapExactTokensForTokens(amountIn, amountOutToken1, path1, address(this), block.timestamp);
        }

        (, , uint256 liquidity) = router.addLiquidity(
            path0[path0Length - 1],
            path1[path1Length - 1],
            amountOutToken0,
            amountOutToken1,
            0,
            0,
            address(this),
            block.timestamp
        );

        return liquidity;
    }

    function checkReward() public view override returns (uint256) {
        return stakingContract.earned(address(this));
    }

    function estimateDeployedBalance() external view override returns (uint256) {
        return stakingContract.balanceOf(address(this));
    }

    function rescueDeployedFunds(uint256 minReturnAmountAccepted, bool disableDeposits) external override onlyOwner {
        uint256 balanceBefore = depositToken.balanceOf(address(this));
        stakingContract.exit();
        uint256 balanceAfter = depositToken.balanceOf(address(this));
        require(balanceAfter.sub(balanceBefore) >= minReturnAmountAccepted, "DexStrategyV4::rescueDeployedFunds");
        totalDeposits = balanceAfter;
        emit Reinvest(totalDeposits, totalSupply);
        if (DEPOSITS_ENABLED == true && disableDeposits == true) {
            updateDepositsEnabled(false);
        }
    }
}
