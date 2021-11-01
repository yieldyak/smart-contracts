// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "./SnowballERC20.sol";
import "./lib/SafeMath.sol";
import "./interfaces/IIceQueen.sol";
import "./interfaces/ISnowGlobe.sol";
import "./interfaces/IRouter.sol";
import "./interfaces/IPair.sol";
import "./interfaces/IERC20.sol";
import "./lib/Ownable.sol";

contract IceQueenStrategyV2b is SnowballERC20, Ownable {
    using SafeMath for uint256;

    uint256 public totalDeposits;

    IRouter public router;
    ISnowGlobe public depositToken;
    IPair public lpToken;
    IERC20 private token0;
    IERC20 private token1;
    IERC20 public rewardToken;
    IIceQueen public stakingContract;

    uint256 public PID;
    uint256 public MIN_TOKENS_TO_REINVEST = 20000;
    uint256 public REINVEST_REWARD_BIPS = 500;
    uint256 public ADMIN_FEE_BIPS = 500;
    uint256 private constant BIPS_DIVISOR = 10000;
    bool public REQUIRE_REINVEST_BEFORE_DEPOSIT;
    uint256 public MIN_TOKENS_TO_REINVEST_BEFORE_DEPOSIT = 20;

    event Deposit(address account, uint256 amount);
    event Withdraw(address account, uint256 amount);
    event Reinvest(uint256 newTotalDeposits, uint256 newTotalSupply);
    event Recovered(address token, uint256 amount);
    event UpdateAdminFee(uint256 oldValue, uint256 newValue);
    event UpdateReinvestReward(uint256 oldValue, uint256 newValue);
    event UpdateMinTokensToReinvest(uint256 oldValue, uint256 newValue);
    event UpdateRequireReinvestBeforeDeposit(bool newValue);
    event UpdateMinTokensToReinvestBeforeDeposit(uint256 oldValue, uint256 newValue);

    constructor(
        address _depositToken,
        address _rewardToken,
        address _stakingContract,
        address _router,
        uint256 _pid
    ) {
        depositToken = ISnowGlobe(_depositToken);
        rewardToken = IERC20(_rewardToken);
        stakingContract = IIceQueen(_stakingContract);
        router = IRouter(_router);

        address _lpToken = ISnowGlobe(_depositToken).token();
        lpToken = IPair(_lpToken);

        PID = _pid;

        address _token0 = IPair(_lpToken).token0();
        address _token1 = IPair(_lpToken).token1();
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);

        name = string(
            abi.encodePacked(
                "Snowball: ",
                ISnowGlobe(_depositToken).symbol(),
                " (",
                lpToken.symbol(),
                " ",
                IERC20(_token0).symbol(),
                "-",
                IERC20(_token1).symbol(),
                ")"
            )
        );

        emit Reinvest(0, 0);
    }

    /**
     * @dev Throws if called by smart contract
     */
    modifier onlyEOA() {
        require(tx.origin == msg.sender, "onlyEOA");
        _;
    }

    /**
     * @notice Set approvals for tokens
     * @param tokensToApprove tokens to approve
     * @param approvalAmounts approval amounts
     * @param spenders address allowed to spend tokens
     */
    function tokenAllow(
        address[] memory tokensToApprove,
        uint256[] memory approvalAmounts,
        address[] memory spenders
    ) external onlyOwner {
        require(
            tokensToApprove.length == approvalAmounts.length && tokensToApprove.length == spenders.length,
            "not same length"
        );
        for (uint256 i = 0; i < tokensToApprove.length; i++) {
            IERC20 token = IERC20(tokensToApprove[i]);
            uint256 allowance = token.allowance(address(this), spenders[i]);
            if (allowance != approvalAmounts[i] && (allowance != uint256(-1) || approvalAmounts[i] == 0)) {
                require(token.approve(spenders[i], approvalAmounts[i]), "approve failed");
            }
        }
    }

    /**
     * @notice Deposit LP tokens to receive Snowball tokens
     * @param amount Amount of LP tokens to deposit
     */
    function deposit(uint256 amount) external {
        require(totalDeposits >= totalSupply, "deposit failed");
        if (REQUIRE_REINVEST_BEFORE_DEPOSIT) {
            uint256 unclaimedRewards = checkReward();
            if (unclaimedRewards >= MIN_TOKENS_TO_REINVEST_BEFORE_DEPOSIT) {
                _reinvest(unclaimedRewards);
            }
        }
        require(depositToken.transferFrom(msg.sender, address(this), amount), "transferFrom failed");
        _stakeDepositTokens(amount);
        _mint(msg.sender, getSharesForLPTokens(amount));
        totalDeposits = totalDeposits.add(amount);
        emit Deposit(msg.sender, amount);
    }

    /**
     * @notice Withdraw deposit tokens by redeeming receipt tokens
     * @param amount Amount of receipt tokens to redeem
     */
    function withdraw(uint256 amount) external {
        uint256 depositTokenAmount = getLPTokensForShares(amount);
        if (depositTokenAmount > 0) {
            _withdrawDepositTokens(depositTokenAmount);
            require(depositToken.transfer(msg.sender, depositTokenAmount), "transfer failed");
            _burn(msg.sender, amount);
            totalDeposits = totalDeposits.sub(depositTokenAmount);
            emit Withdraw(msg.sender, depositTokenAmount);
        }
    }

    /**
     * @notice Calculate receipt tokens for a given amount of deposit tokens
     * @dev If contract is empty, use 1:1 ratio
     * @dev Could return zero shares for very low amounts of deposit tokens
     * @dev Note: misleading name (consider rename to "getReceiptTokensForDepositTokens")
     * @param amount deposit tokens
     * @return receipt tokens
     */
    function getSharesForLPTokens(uint256 amount) public view returns (uint256) {
        if (totalSupply.mul(totalDeposits) == 0) {
            return amount;
        }
        return amount.mul(totalSupply).div(totalDeposits);
    }

    /**
     * @notice Calculate deposit tokens for a given amount of receipt tokens
     * @dev Note: misleading name (consider rename to "getDepositTokensForReceiptTokens")
     * @param amount receipt tokens
     * @return deposit tokens
     */
    function getLPTokensForShares(uint256 amount) public view returns (uint256) {
        if (totalSupply.mul(totalDeposits) == 0) {
            return 0;
        }
        return amount.mul(totalDeposits).div(totalSupply);
    }

    /**
     * @notice Reward token balance that can be reinvested
     * @dev Staking rewards accurue to contract on each deposit/withdrawal
     * @return Unclaimed rewards, plus contract balance
     */
    function checkReward() public view returns (uint256) {
        uint256 pendingReward = stakingContract.pendingSnowball(PID, address(this));
        uint256 contractBalance = rewardToken.balanceOf(address(this));
        return pendingReward.add(contractBalance);
    }

    /**
     * @notice Estimate reinvest reward
     * @return Estimated reward tokens earned for calling `reinvest()`
     */
    function estimateReinvestReward() external view returns (uint256) {
        uint256 unclaimedRewards = checkReward();
        if (unclaimedRewards >= MIN_TOKENS_TO_REINVEST) {
            return unclaimedRewards.mul(REINVEST_REWARD_BIPS).div(BIPS_DIVISOR);
        }
        return 0;
    }

    /**
     * @notice Reinvest rewards from staking contract to LP tokens
     * @dev This external function requires minimum tokens to be met
     */
    function reinvest() external onlyEOA {
        uint256 unclaimedRewards = checkReward();
        require(unclaimedRewards >= MIN_TOKENS_TO_REINVEST, "MIN_TOKENS_TO_REINVEST");
        _reinvest(unclaimedRewards);
    }

    /**
     * @notice Reinvest rewards from staking contract to deposit tokens
     */
    function _reinvest(uint256 amount) internal {
        stakingContract.deposit(PID, 0);

        uint256 adminFee = amount.mul(ADMIN_FEE_BIPS).div(BIPS_DIVISOR);
        if (adminFee > 0) {
            require(rewardToken.transfer(owner(), adminFee), "admin fee transfer failed");
        }

        uint256 reinvestFee = amount.mul(REINVEST_REWARD_BIPS).div(BIPS_DIVISOR);
        if (reinvestFee > 0) {
            require(rewardToken.transfer(msg.sender, reinvestFee), "reinvest fee transfer failed");
        }

        uint256 lpTokenAmount = _convertRewardTokensToLpTokens(amount.sub(adminFee).sub(reinvestFee));
        uint256 depositTokenAmount = _convertLpTokensToDepositTokens(lpTokenAmount);
        _stakeDepositTokens(depositTokenAmount);
        totalDeposits = totalDeposits.add(depositTokenAmount);

        emit Reinvest(totalDeposits, totalSupply);
    }

    /**
     * @notice Converts intermediary LP tokens to deposit tokens
     * @dev Function `deposit(uint)` does not return an amount and is calculated
     * @dev Do NOT rely on output amount for non-standard token supply mechanisms (e.g. fee on transfer)
     * @return deposit tokens received
     */
    function _convertLpTokensToDepositTokens(uint256 amount) internal returns (uint256) {
        require(amount > 0, "amount too low");
        uint256 _pool = depositToken.balance();
        uint256 _totalSupply = depositToken.totalSupply();
        uint256 shares = 0;
        if (_totalSupply == 0) {
            shares = amount;
        } else {
            shares = (amount.mul(_totalSupply)).div(_pool);
        }
        depositToken.deposit(amount);
        return shares;
    }

    /**
     * @notice Converts entire reward token balance to intermediary LP tokens
     * @dev Always converts through router; there are no price checks enabled
     * @return LP tokens received
     */
    function _convertRewardTokensToLpTokens(uint256 amount) internal returns (uint256) {
        uint256 amountIn = amount.div(2);
        require(amountIn > 0, "amount too low");

        // swap to token0
        address[] memory path0 = new address[](2);
        path0[0] = address(rewardToken);
        path0[1] = address(token0);

        uint256 amountOutToken0 = amountIn;
        if (path0[0] != path0[path0.length - 1]) {
            uint256[] memory amountsOutToken0 = router.getAmountsOut(amountIn, path0);
            amountOutToken0 = amountsOutToken0[amountsOutToken0.length - 1];
            router.swapExactTokensForTokens(amountIn, amountOutToken0, path0, address(this), block.timestamp);
        }

        // swap to token1
        address[] memory path1 = new address[](3);
        path1[0] = path0[0];
        path1[1] = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
        path1[2] = address(token1);

        uint256 amountOutToken1 = amountIn;
        if (path1[0] != path1[path1.length - 1]) {
            uint256[] memory amountsOutToken1 = router.getAmountsOut(amountIn, path1);
            amountOutToken1 = amountsOutToken1[amountsOutToken1.length - 1];
            router.swapExactTokensForTokens(amountIn, amountOutToken1, path1, address(this), block.timestamp);
        }

        (, , uint256 liquidity) = router.addLiquidity(
            path0[path0.length - 1],
            path1[path1.length - 1],
            amountOutToken0,
            amountOutToken1,
            0,
            0,
            address(this),
            block.timestamp
        );

        return liquidity;
    }

    /**
     * @notice Stakes deposit tokens in Staking Contract
     * @param amount deposit tokens to stake
     */
    function _stakeDepositTokens(uint256 amount) internal {
        require(amount > 0, "amount too low");
        stakingContract.deposit(PID, amount);
    }

    /**
     * @notice Withdraws deposit tokens from Staking Contract
     * @dev Reward tokens are automatically collected
     * @dev Reward tokens are not automatically reinvested
     * @param amount deposit tokens to remove
     */
    function _withdrawDepositTokens(uint256 amount) internal {
        require(amount > 0, "amount too low");
        stakingContract.withdraw(PID, amount);
    }

    /**
     * @notice Allows exit from Staking Contract without additional logic
     * @dev Reward tokens are not automatically collected
     * @dev New deposits will be effectively disabled
     */
    function emergencyWithdraw() external onlyOwner {
        stakingContract.emergencyWithdraw(PID);
        totalDeposits = 0;
    }

    /**
     * @notice Update reinvest minimum threshold for external callers
     * @param newValue min threshold in wei
     */
    function updateMinTokensToReinvest(uint256 newValue) external onlyOwner {
        emit UpdateMinTokensToReinvest(MIN_TOKENS_TO_REINVEST, newValue);
        MIN_TOKENS_TO_REINVEST = newValue;
    }

    /**
     * @notice Update admin fee
     * @dev Total fees cannot be greater than BIPS_DIVISOR (100%)
     * @param newValue specified in BIPS
     */
    function updateAdminFee(uint256 newValue) external onlyOwner {
        require(newValue.add(REINVEST_REWARD_BIPS) <= BIPS_DIVISOR, "admin fee too high");
        emit UpdateAdminFee(ADMIN_FEE_BIPS, newValue);
        ADMIN_FEE_BIPS = newValue;
    }

    /**
     * @notice Update reinvest reward
     * @dev Total fees cannot be greater than BIPS_DIVISOR (100%)
     * @param newValue specified in BIPS
     */
    function updateReinvestReward(uint256 newValue) external onlyOwner {
        require(newValue.add(ADMIN_FEE_BIPS) <= BIPS_DIVISOR, "reinvest reward too high");
        emit UpdateReinvestReward(REINVEST_REWARD_BIPS, newValue);
        REINVEST_REWARD_BIPS = newValue;
    }

    /**
     * @notice Toggle requirement to reinvest before deposit
     */
    function updateRequireReinvestBeforeDeposit() external onlyOwner {
        REQUIRE_REINVEST_BEFORE_DEPOSIT = !REQUIRE_REINVEST_BEFORE_DEPOSIT;
        emit UpdateRequireReinvestBeforeDeposit(REQUIRE_REINVEST_BEFORE_DEPOSIT);
    }

    /**
     * @notice Update reinvest minimum threshold before a deposit
     * @param newValue min threshold in wei
     */
    function updateMinTokensToReinvestBeforeDeposit(uint256 newValue) external onlyOwner {
        emit UpdateMinTokensToReinvestBeforeDeposit(MIN_TOKENS_TO_REINVEST_BEFORE_DEPOSIT, newValue);
        MIN_TOKENS_TO_REINVEST_BEFORE_DEPOSIT = newValue;
    }

    /**
     * @notice Recover ERC20 from contract
     * @param tokenAddress token address
     * @param tokenAmount amount to recover
     */
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        require(tokenAmount > 0, "amount too low");
        IERC20(tokenAddress).transfer(msg.sender, tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    /**
     * @notice Recover AVAX from contract
     * @param amount amount
     */
    function recoverAVAX(uint256 amount) external onlyOwner {
        require(amount > 0, "amount too low");
        msg.sender.transfer(amount);
        emit Recovered(address(0), amount);
    }
}
