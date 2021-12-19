// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

import "../YakStrategy.sol";
import "../interfaces/IStakingRewards.sol";

/**
 * @notice Single Asset strategy for StakingRewards
 */
contract DexStrategySA is YakStrategy {
    using SafeMath for uint;

    IStakingRewards public stakingContract;

    constructor (
        string memory _name,
        string memory _symbol,
        address _depositToken,
        address _rewardToken,
        address _stakingContract,
        address _timelock,
        uint _minTokensToReinvest,
        uint _devFeeBips,
        uint _reinvestRewardBips
    ) {
        name = _name;
        symbol = _symbol;
        depositToken = IERC20(_depositToken);
        rewardToken = IERC20(_rewardToken);
        stakingContract = IStakingRewards(_stakingContract);
        devAddr = 0x2D580F9CF2fB2D09BC411532988F2aFdA4E7BefF;

        updateMinTokensToReinvest(_minTokensToReinvest);
        updateDevFee(_devFeeBips);
        updateReinvestReward(_reinvestRewardBips);
        updateDepositsEnabled(true);
        transferOwnership(_timelock);

        emit Reinvest(0, 0);
    }

    function setAllowances() public override onlyOwner {
        revert("Deprecated");
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
        require(DEPOSITS_ENABLED == true, "DexStrategySA::_deposit");
        if (MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST > 0) {
            uint unclaimedRewards = checkReward();
            if (unclaimedRewards > MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST) {
                _reinvest(unclaimedRewards);
            }
        }
        require(depositToken.transferFrom(msg.sender, address(this), amount));
        _mint(account, getSharesForDepositTokens(amount));
        _stakeDepositTokens(amount);
        totalDeposits = totalDeposits.add(amount);
        emit Deposit(account, amount);
    }

    function withdraw(uint amount) external override {
        uint depositTokenAmount = getDepositTokensForShares(amount);
        require(depositTokenAmount > 0, "DexStrategySA::withdraw");
        _burn(msg.sender, amount);
        totalDeposits = totalDeposits.sub(depositTokenAmount);
        emit Withdraw(msg.sender, depositTokenAmount);
        _withdrawDepositTokens(depositTokenAmount);
    }

    function _withdrawDepositTokens(uint amount) private {
        stakingContract.withdraw(amount);
        require(depositToken.transfer(msg.sender, amount), "DexStrategySA::_withdrawDepositTokens");
    }

    function reinvest() external override onlyEOA {
        uint unclaimedRewards = checkReward();
        require(unclaimedRewards >= MIN_TOKENS_TO_REINVEST, "DexStrategySA::reinvest");
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
            require(rewardToken.transfer(devAddr, devFee), "DexStrategySA::_reinvest, dev");
        }

        uint reinvestFee = amount.mul(REINVEST_REWARD_BIPS).div(BIPS_DIVISOR);
        if (reinvestFee > 0) {
            require(rewardToken.transfer(msg.sender, reinvestFee), "DexStrategySA::_reinvest, reward");
        }

        uint depositTokenAmount = amount.sub(devFee).sub(reinvestFee);

        _stakeDepositTokens(depositTokenAmount);
        totalDeposits = totalDeposits.add(depositTokenAmount);

        emit Reinvest(totalDeposits, totalSupply);
    }
    
    function _stakeDepositTokens(uint amount) private {
        require(amount > 0, "DexStrategySA::_stakeDepositTokens");
        depositToken.approve(address(stakingContract), amount);
        stakingContract.stake(amount);
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
        depositToken.approve(address(stakingContract), 0);
        uint balanceAfter = depositToken.balanceOf(address(this));
        require(balanceAfter.sub(balanceBefore) >= minReturnAmountAccepted, "DexStrategySA::rescueDeployedFunds");
        totalDeposits = balanceAfter;
        emit Reinvest(totalDeposits, totalSupply);
        updateDepositsEnabled(false);
    }
}