// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "../YakStrategy.sol";
import "../interfaces/IStakingRewards.sol";
import "../interfaces/IPair.sol";
import "../interfaces/IWAVAX.sol";

/**
 * @notice Single-asset strategy for Accepting AVAX StakingRewards with different reward token
 * @dev Assumes conversion is handled through one `swapPair` and AVAX is transferred to the contract beforehand
 */
contract CompoundingAvax is YakStrategy {
    using SafeMath for uint;
    address public WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    IStakingRewards public stakingContract;
    IPair private swapPair;
    bytes private constant zeroBytes = new bytes(0);
    event Received(address,uint);

    constructor (
        string memory _name,
        string memory _symbol,
        address _depositToken,
        address _rewardToken,
        address _stakingContract,
        address _swapPair,
        address _timelock,
        uint _minTokensToReinvest,
        uint _adminFeeBips,
        uint _devFeeBips,
        uint _reinvestRewardBips
    ) {
        name = _name;
        symbol = _symbol;
        depositToken = _depositToken;
        rewardToken = IERC20(_rewardToken);
        stakingContract = IStakingRewards(_stakingContract);
        swapPair = IPair(_swapPair);
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
        IWAVAX(WAVAX).approve(address(stakingContract), MAX_UINT);
    }

    receive() external payable {

        emit Received(msg.sender, msg.value); // only accept AVAX via fallback from the WAVAX contract
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

    function depositAVAX(address account, uint amountAVAX) external payable {
        require(DEPOSITS_ENABLED == true, "DexStrategySAWithSwapV2::_deposit");
        if (MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST > 0) {
            uint unclaimedRewards = checkReward();
            if (unclaimedRewards > MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST) {
                _reinvest(unclaimedRewards);
            }
        }
        IWAVAX(WAVAX).deposit{value: amountAVAX}();
        require(IWAVAX(WAVAX).transfer(address(this), amountAVAX));
        _stakeDepositTokens(amountAVAX);
        _mint(account, getSharesForDepositTokens(amountAVAX));
        totalDeposits = totalDeposits.add(amountAVAX);
        emit Deposit(account, amountAVAX);
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
            _safeTransfer(address(depositToken), msg.sender, depositTokenAmount);
            _burn(msg.sender, amount);
            totalDeposits = totalDeposits.sub(depositTokenAmount);
            emit Withdraw(msg.sender, depositTokenAmount);
        }
    }

/**
     * @notice Safely transfer AVAX
     * @dev Requires token to return true on transfer
     * @param to recipient address
     * @param intValue amount
     */
    function _safeTransferAVAX(address payable to, uint256 intValue) internal {
        (bool success, ) = to.call{value: intValue}("");
        require(success, 'TransferHelper: AVAX_TRANSFER_FAILED');
    }

    function withdrawAVAX(uint amountAVAX) external {
        uint depositTokenAmount = getDepositTokensForShares(amountAVAX);
        if (depositTokenAmount > 0) {
            _withdrawDepositTokens(depositTokenAmount);
            IWAVAX(WAVAX).withdraw(depositTokenAmount);
            _safeTransferAVAX(msg.sender, depositTokenAmount);
            _burn(msg.sender, amountAVAX);
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
            _safeTransfer(address(rewardToken), devAddr, devFee);
        }

        uint adminFee = amount.mul(ADMIN_FEE_BIPS).div(BIPS_DIVISOR);
        if (adminFee > 0) {
            _safeTransfer(address(rewardToken), owner(), adminFee);
        }

        uint reinvestFee = amount.mul(REINVEST_REWARD_BIPS).div(BIPS_DIVISOR);
        if (reinvestFee > 0) {
            _safeTransfer(address(rewardToken), msg.sender, reinvestFee);
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
     * @notice Safely transfer using an anonymosu ERC20 token
     * @dev Requires token to return true on transfer
     * @param token address
     * @param to recipient address
     * @param value amount
     */
    function _safeTransfer(address token, address to, uint256 value) private {
        require(IERC20(token).transfer(to, value), 'TransferHelper: TRANSFER_FROM_FAILED');
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
        _safeTransfer(fromToken, address(pair), amountIn);
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