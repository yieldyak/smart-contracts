// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

import "../YakStrategy.sol";
import "../interfaces/IStakingRewards.sol";
import "../interfaces/IRouter.sol";

/**
 * @notice Single-asset strategy for StakingRewards with different reward token
 */
contract DexStrategySAWithSwap is YakStrategy {
    using SafeMath for uint;

    IStakingRewards public stakingContract;
    IRouter public router;

    constructor (
        string memory _name,
        string memory _symbol,
        address _depositToken,
        address _rewardToken,
        address _stakingContract,
        address _router,
        address _timelock,
        uint _minTokensToReinvest,
        uint _adminFeeBips,
        uint _devFeeBips,
        uint _reinvestRewardBips
    ) {
        name = _name;
        symbol = _symbol;
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
        require(DEPOSITS_ENABLED == true, "DexStrategySAWithSwap::_deposit");
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
            require(depositToken.transfer(msg.sender, depositTokenAmount), "DexStrategySAWithSwap::withdraw");
            _burn(msg.sender, amount);
            totalDeposits = totalDeposits.sub(depositTokenAmount);
            emit Withdraw(msg.sender, depositTokenAmount);
        }
    }

    function _withdrawDepositTokens(uint amount) private {
        require(amount > 0, "DexStrategySAWithSwap::_withdrawDepositTokens");
        stakingContract.withdraw(amount);
    }

    function reinvest() external override onlyEOA {
        uint unclaimedRewards = checkReward();
        require(unclaimedRewards >= MIN_TOKENS_TO_REINVEST, "DexStrategySAWithSwap::reinvest");
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
            require(rewardToken.transfer(devAddr, devFee), "DexStrategySAWithSwap::_reinvest, dev");
        }

        uint adminFee = amount.mul(ADMIN_FEE_BIPS).div(BIPS_DIVISOR);
        if (adminFee > 0) {
            require(rewardToken.transfer(owner(), adminFee), "DexStrategySAWithSwap::_reinvest, admin");
        }

        uint reinvestFee = amount.mul(REINVEST_REWARD_BIPS).div(BIPS_DIVISOR);
        if (reinvestFee > 0) {
            require(rewardToken.transfer(msg.sender, reinvestFee), "DexStrategySAWithSwap::_reinvest, reward");
        }

        uint depositTokenAmount = _convertRewardTokensToDepositTokens(
            amount.sub(devFee).sub(adminFee).sub(reinvestFee)
        );

        _stakeDepositTokens(depositTokenAmount);
        totalDeposits = totalDeposits.add(depositTokenAmount);

        emit Reinvest(totalDeposits, totalSupply);
    }
    
    function _stakeDepositTokens(uint amount) private {
        require(amount > 0, "DexStrategySAWithSwap::_stakeDepositTokens");
        stakingContract.stake(amount);
    }

    /**
     * @notice Converts reward tokens to deposit tokens
     * @dev Always converts through router; there are no price checks enabled
     * @return deposit tokens received
     */
    function _convertRewardTokensToDepositTokens(uint amount) private returns (uint) {
        require(amount > 0, "DexStrategySAWithSwap::_convertRewardTokensToDepositTokens");

        uint pathLength = 2;
        address[] memory path = new address[](pathLength);
        path[0] = address(rewardToken);
        path[1] = address(depositToken);

        uint amountOutToken = amount;
        uint[] memory amountsOutToken = router.getAmountsOut(amount, path);
        amountOutToken = amountsOutToken[amountsOutToken.length - 1];
        router.swapExactTokensForTokens(amount, amountOutToken, path, address(this), block.timestamp);

        return amountOutToken;
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
        require(balanceAfter.sub(balanceBefore) >= minReturnAmountAccepted, "DexStrategySAWithSwap::rescueDeployedFunds");
        totalDeposits = balanceAfter;
        emit Reinvest(totalDeposits, totalSupply);
        if (DEPOSITS_ENABLED == true && disableDeposits == true) {
            updateDepositsEnabled(false);
        }
    }
}