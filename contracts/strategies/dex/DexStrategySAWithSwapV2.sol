// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../YakStrategy.sol";
import "./interfaces/IStakingRewards.sol";
import "../../interfaces/IPair.sol";
import "../../lib/SafeERC20.sol";

/**
 * @notice Single-asset strategy for StakingRewards with different reward token
 * @dev Assumes conversion is handled through one `swapPair`
 */
contract DexStrategySAWithSwapV2 is YakStrategy {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    IStakingRewards public stakingContract;
    IPair private swapPair;
    bytes private constant zeroBytes = new bytes(0);

    constructor (
        string memory _name,
        string memory _symbol,
        address _depositToken,
        address _rewardToken,
        address _stakingContract,
        address _swapPair,
        address _timelock,
        StrategySettings memory _strategySettings
    ) {
        name = _name;
        symbol = _symbol;
        depositToken = IERC20(_depositToken);
        rewardToken = IERC20(_rewardToken);
        stakingContract = IStakingRewards(_stakingContract);
        swapPair = IPair(_swapPair);
        devAddr = msg.sender;

        setAllowances();
        applyStrategySettings(_strategySettings);
        updateDepositsEnabled(true);
        transferOwnership(_timelock);

        emit Reinvest(0, 0);
    }

    function setAllowances() public override onlyOwner {
        depositToken.approve(address(stakingContract), MAX_UINT);
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
        require(DEPOSITS_ENABLED == true, "DexStrategySAWithSwapV2::_deposit");
        if (MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST > 0) {
            uint unclaimedRewards = checkReward();
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

    function withdraw(uint amount) external override {
        uint depositTokenAmount = getDepositTokensForShares(amount);
        if (depositTokenAmount > 0) {
            _withdrawDepositTokens(depositTokenAmount);
            IERC20(address(depositToken)).safeTransfer(msg.sender, depositTokenAmount);
            _burn(msg.sender, amount);
            totalDeposits = totalDeposits.sub(depositTokenAmount);
            emit Withdraw(msg.sender, depositTokenAmount);
        }
    }

    function _withdrawDepositTokens(uint amount) private {
        require(amount > 0, "DexStrategySAWithSwapV2::_withdrawDepositTokens");
        stakingContract.withdraw(amount);
    }

    function reinvest() external override onlyEOA {
        uint unclaimedRewards = checkReward();
        require(unclaimedRewards >= MIN_TOKENS_TO_REINVEST, "DexStrategySAWithSwapV2::reinvest");
        _reinvest(unclaimedRewards);
    }

    /**
     * @notice Reinvest rewards from staking contract to deposit tokens
     * @dev Reverts if the expected amount of tokens are not returned from `stakingContract`
     * @param amount deposit tokens to reinvest
     */
    function _reinvest(uint amount) private {
        stakingContract.getReward();

        uint devFee = amount.mul(DEV_FEE_BIPS).div(BIPS_DIVISOR);
        if (devFee > 0) {
            IERC20(address(rewardToken)).safeTransfer(devAddr, devFee);
        }

        uint adminFee = amount.mul(ADMIN_FEE_BIPS).div(BIPS_DIVISOR);
        if (adminFee > 0) {
            IERC20(address(rewardToken)).safeTransfer(owner(), adminFee);
        }

        uint reinvestFee = amount.mul(REINVEST_REWARD_BIPS).div(BIPS_DIVISOR);
        if (reinvestFee > 0) {
            IERC20(address(rewardToken)).safeTransfer(msg.sender, reinvestFee);
        }

        uint depositTokenAmount = _convertRewardTokensToDepositTokens(
            amount.sub(devFee).sub(adminFee).sub(reinvestFee)
        );

        _stakeDepositTokens(depositTokenAmount);
        totalDeposits = totalDeposits.add(depositTokenAmount);

        emit Reinvest(totalDeposits, totalSupply);
    }
    
    function _stakeDepositTokens(uint amount) private {
        require(amount > 0, "DexStrategySAWithSwapV2::_stakeDepositTokens");
        stakingContract.stake(amount);
    }

    /** 
     * @notice Given two tokens, it'll return the tokens in the right order for the tokens pair
     * @dev TokenA must be different from TokenB, and both shouldn't be address(0), no validations
     * @param tokenA address
     * @param tokenB address
     * @return sorted tokens
     */
    function _sortTokens(address tokenA, address tokenB) private pure returns (address, address) {
        return tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    /**
     * @notice Given an input amount of an asset and pair reserves, returns maximum output amount of the other asset
     * @dev Assumes swap fee is 0.30%
     * @param amountIn input asset
     * @param reserveIn size of input asset reserve
     * @param reserveOut size of output asset reserve
     * @return maximum output amount
     */  
    function _getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) private pure returns (uint) {
        uint amountInWithFee = amountIn.mul(997);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        return numerator.div(denominator);
    }

    /**
     * @notice Swap directly through a Pair
     * @param amountIn input amount
     * @param fromToken address
     * @param toToken address
     * @param pair Pair used for swap
     * @return output amount
     */
    function _swap(uint amountIn, address fromToken, address toToken, IPair pair) private returns (uint) {
        (address token0,) = _sortTokens(fromToken, toToken);
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        if (token0 != fromToken) (reserve0, reserve1) = (reserve1, reserve0);
        uint amountOut1 = 0;
        uint amountOut2 = _getAmountOut(amountIn, reserve0, reserve1);
        if (token0 != fromToken) (amountOut1, amountOut2) = (amountOut2, amountOut1);
        IERC20(fromToken).safeTransfer(address(pair), amountIn);
        pair.swap(amountOut1, amountOut2, address(this), zeroBytes);
        return amountOut2 > amountOut1 ? amountOut2 : amountOut1;
    }

    /**
     * @notice Converts reward tokens to deposit tokens
     * @dev Always converts through router; there are no price checks enabled
     * @return deposit tokens received
     */
    function _convertRewardTokensToDepositTokens(uint amount) private returns (uint) {
        require(amount > 0, "DexStrategySAWithSwapV2::_convertRewardTokensToDepositTokens");
        return _swap(amount, address(rewardToken), address(depositToken), swapPair);
    }

    
    function checkReward() public override view returns (uint) {
        return stakingContract.earned(address(this));
    }

    function estimateDeployedBalance() external override view returns (uint) {
        return stakingContract.balanceOf(address(this));
    }

    function rescueDeployedFunds(uint minReturnAmountAccepted, bool disableDeposits) external override onlyOwner {
        uint balanceBefore = depositToken.balanceOf(address(this));
        stakingContract.exit();
        uint balanceAfter = depositToken.balanceOf(address(this));
        require(balanceAfter.sub(balanceBefore) >= minReturnAmountAccepted, "DexStrategySAWithSwapV2::rescueDeployedFunds");
        totalDeposits = balanceAfter;
        emit Reinvest(totalDeposits, totalSupply);
        if (DEPOSITS_ENABLED == true && disableDeposits == true) {
            updateDepositsEnabled(false);
        }
    }
}