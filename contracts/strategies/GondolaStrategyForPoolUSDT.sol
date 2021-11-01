// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "../YakStrategy.sol";
import "../interfaces/IGondolaChef.sol";
import "../interfaces/IRouter.sol";
import "../interfaces/IPair.sol";
import "../interfaces/IGondolaPool.sol";

/**
 * @notice StableSwap strategy for Gondola USDT/zUSDT
 */
contract GondolaStrategyForPoolUSDT is YakStrategy {
    using SafeMath for uint256;

    IRouter public router;
    IGondolaChef public stakingContract;
    IGondolaPool public poolContract;

    address private constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    address private constant USDT = 0xde3A24028580884448a5397872046a019649b084;
    address private constant ZUSDT = 0x650CECaFE61f3f65Edd21eFacCa18Cc905EeF0B7;
    address private constant ZERO = 0x008E26068B3EB40B443d3Ea88c1fF99B789c10F7;
    IRouter private constant PANGO_ROUTER = IRouter(0xE54Ca86531e17Ef3616d22Ca28b0D458b6C89106);
    IRouter private constant ZERO_ROUTER = IRouter(0x85995d5f8ee9645cA855e92de16FA62D26398060);

    uint256 public PID;

    constructor(
        string memory _name,
        address _depositToken,
        address _rewardToken,
        address _stakingContract,
        address _poolContract,
        address _timelock,
        uint256 _pid,
        uint256 _minTokensToReinvest,
        uint256 _adminFeeBips,
        uint256 _devFeeBips,
        uint256 _reinvestRewardBips
    ) {
        name = _name;
        depositToken = IPair(_depositToken);
        rewardToken = IERC20(_rewardToken);
        stakingContract = IGondolaChef(_stakingContract);
        poolContract = IGondolaPool(_poolContract);
        PID = _pid;
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

    /**
     * @notice Approve tokens for use in Strategy
     * @dev Restricted to avoid griefing attacks
     */
    function setAllowances() public override onlyOwner {
        depositToken.approve(address(stakingContract), MAX_UINT);
        rewardToken.approve(address(PANGO_ROUTER), MAX_UINT);
        rewardToken.approve(address(ZERO_ROUTER), MAX_UINT);
        IERC20(USDT).approve(address(poolContract), MAX_UINT);
        IERC20(ZUSDT).approve(address(poolContract), MAX_UINT);
    }

    /**
     * @notice Deposit tokens to receive receipt tokens
     * @param amount Amount of tokens to deposit
     */
    function deposit(uint256 amount) external override {
        _deposit(msg.sender, amount);
    }

    /**
     * @notice Deposit using Permit
     * @param amount Amount of tokens to deposit
     * @param deadline The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
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

    function _deposit(address account, uint256 amount) internal {
        require(DEPOSITS_ENABLED == true, "GondolaStrategyForStableSwap::_deposit");
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
            require(depositToken.transfer(msg.sender, depositTokenAmount), "GondolaStrategyForStableSwap::withdraw");
            _burn(msg.sender, amount);
            totalDeposits = totalDeposits.sub(depositTokenAmount);
            emit Withdraw(msg.sender, depositTokenAmount);
        }
    }

    function _withdrawDepositTokens(uint256 amount) private {
        require(amount > 0, "GondolaStrategyForStableSwap::_withdrawDepositTokens");
        stakingContract.withdraw(PID, amount);
    }

    function reinvest() external override onlyEOA {
        uint256 unclaimedRewards = checkReward();
        require(unclaimedRewards >= MIN_TOKENS_TO_REINVEST, "GondolaStrategyForStableSwap::reinvest");
        _reinvest(unclaimedRewards);
    }

    /**
     * @notice Reinvest rewards from staking contract to deposit tokens
     * @dev Reverts if the expected amount of tokens are not returned from `stakingContract`
     * @param amount deposit tokens to reinvest
     */
    function _reinvest(uint256 amount) private {
        stakingContract.deposit(PID, 0);

        uint256 devFee = amount.mul(DEV_FEE_BIPS).div(BIPS_DIVISOR);
        if (devFee > 0) {
            require(rewardToken.transfer(devAddr, devFee), "GondolaStrategyForStableSwap::_reinvest, dev");
        }

        uint256 adminFee = amount.mul(ADMIN_FEE_BIPS).div(BIPS_DIVISOR);
        if (adminFee > 0) {
            require(rewardToken.transfer(owner(), adminFee), "GondolaStrategyForStableSwap::_reinvest, admin");
        }

        uint256 reinvestFee = amount.mul(REINVEST_REWARD_BIPS).div(BIPS_DIVISOR);
        if (reinvestFee > 0) {
            require(rewardToken.transfer(msg.sender, reinvestFee), "GondolaStrategyForStableSwap::_reinvest, reward");
        }

        uint256 depositTokenAmount = _convertRewardTokensToDepositTokens(
            amount.sub(devFee).sub(adminFee).sub(reinvestFee)
        );

        _stakeDepositTokens(depositTokenAmount);
        totalDeposits = totalDeposits.add(depositTokenAmount);

        emit Reinvest(totalDeposits, totalSupply);
    }

    function _stakeDepositTokens(uint256 amount) private {
        require(amount > 0, "GondolaStrategyForStableSwap::_stakeDepositTokens");
        stakingContract.deposit(PID, amount);
    }

    function checkReward() public view override returns (uint256) {
        uint256 pendingReward = stakingContract.pendingGondola(PID, address(this));
        uint256 contractBalance = rewardToken.balanceOf(address(this));
        return pendingReward.add(contractBalance);
    }

    /**
     * @notice Converts reward tokens to deposit tokens
     * @dev Always converts through router; there are no price checks enabled
     * @return deposit tokens received
     */
    function _convertRewardTokensToDepositTokens(uint256 amount) private returns (uint256) {
        require(amount > 0, "GondolaStrategyForStableSwap::_convertRewardTokensToDepositTokens");

        IRouter _router;
        uint256[] memory liquidityAmounts = new uint256[](2);
        address[] memory path = new address[](3);
        path[0] = address(rewardToken);

        // find route for bonus token
        if (poolContract.getTokenBalance(0) < poolContract.getTokenBalance(1)) {
            // convert to 0
            path[1] = WAVAX;
            path[2] = USDT;
            _router = PANGO_ROUTER;
            uint256[] memory amountsOutToken = _router.getAmountsOut(amount, path);
            uint256 amountOutToken = amountsOutToken[amountsOutToken.length - 1];
            _router.swapExactTokensForTokens(amount, amountOutToken, path, address(this), block.timestamp);
            liquidityAmounts[0] = amountOutToken;
        } else {
            // convert to 1
            path[1] = ZERO;
            path[2] = ZUSDT;
            _router = ZERO_ROUTER;
            uint256[] memory amountsOutToken = _router.getAmountsOut(amount, path);
            uint256 amountOutToken = amountsOutToken[amountsOutToken.length - 1];
            _router.swapExactTokensForTokens(amount, amountOutToken, path, address(this), block.timestamp);
            liquidityAmounts[1] = amountOutToken;
        }

        uint256 liquidity = poolContract.addLiquidity(liquidityAmounts, 0, block.timestamp);
        return liquidity;
    }

    /**
     * @notice Estimate recoverable balance
     * @return deposit tokens
     */
    function estimateDeployedBalance() external view override returns (uint256) {
        (uint256 depositBalance, ) = stakingContract.userInfo(PID, address(this));
        return depositBalance;
    }

    function rescueDeployedFunds(uint256 minReturnAmountAccepted, bool disableDeposits) external override onlyOwner {
        uint256 balanceBefore = depositToken.balanceOf(address(this));
        stakingContract.emergencyWithdraw(PID);
        uint256 balanceAfter = depositToken.balanceOf(address(this));
        require(
            balanceAfter.sub(balanceBefore) >= minReturnAmountAccepted,
            "GondolaStrategyForStableSwap::rescueDeployedFunds"
        );
        totalDeposits = balanceAfter;
        emit Reinvest(totalDeposits, totalSupply);
        if (DEPOSITS_ENABLED == true && disableDeposits == true) {
            updateDepositsEnabled(false);
        }
    }
}
