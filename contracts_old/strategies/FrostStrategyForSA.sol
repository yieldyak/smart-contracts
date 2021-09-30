// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "../YakStrategy.sol";
import "../interfaces/IFrostChef.sol";
import "../interfaces/IPair.sol";
import "../lib/DexLibrary.sol";

/**
 * @notice Strategy for Frost
 */
contract FrostStrategyForSA is YakStrategy {
  using SafeMath for uint;

  IFrostChef public stakingContract;
  IPair private swapPairToken;
  IPair private swapPairWAVAXTundra;
  address private constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;

  uint public PID;

  constructor(
    string memory _name,
    address _depositToken, 
    address _rewardToken, 
    address _stakingContract,
    address _swapPairWAVAXTundra,
    address _swapPairToken,
    address _timelock,
    uint _pid,
    uint _minTokensToReinvest,
    uint _adminFeeBips,
    uint _devFeeBips,
    uint _reinvestRewardBips
  ) {
    name = _name;
    depositToken = IPair(_depositToken);
    rewardToken = IERC20(_rewardToken);
    stakingContract = IFrostChef(_stakingContract);
    swapPairWAVAXTundra = IPair(_swapPairWAVAXTundra);
    swapPairToken = IPair(_swapPairToken);
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
  }

  /**
   * @notice Deposit tokens to receive receipt tokens
   * @param amount Amount of tokens to deposit
   */
  function deposit(uint amount) external override {
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
  function depositWithPermit(uint amount, uint deadline, uint8 v, bytes32 r, bytes32 s) external override {
    depositToken.permit(msg.sender, address(this), amount, deadline, v, r, s);
    _deposit(msg.sender, amount);
  }

  function depositFor(address account, uint amount) external override {
      _deposit(account, amount);
  }

  function _deposit(address account, uint amount) internal {
    require(DEPOSITS_ENABLED == true, "FrostStrategyForSA::_deposit");
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
      (,,,, uint withdrawFeeBP) = stakingContract.poolInfo(PID);
      uint withdrawFee = depositTokenAmount.mul(withdrawFeeBP).div(BIPS_DIVISOR);
      _safeTransfer(address(depositToken), msg.sender, depositTokenAmount.sub(withdrawFee));
      _burn(msg.sender, amount);
      totalDeposits = totalDeposits.sub(depositTokenAmount);
      emit Withdraw(msg.sender, depositTokenAmount);
    }
  }

  function _withdrawDepositTokens(uint amount) private {
    require(amount > 0, "FrostStrategyForSA::_withdrawDepositTokens");
    stakingContract.withdraw(PID, amount);
  }

  function reinvest() external override onlyEOA {
    uint unclaimedRewards = checkReward();
    require(unclaimedRewards >= MIN_TOKENS_TO_REINVEST, "FrostStrategyForSA::reinvest");
    _reinvest(unclaimedRewards);
  }

  /**
    * @notice Reinvest rewards from staking contract to deposit tokens
    * @dev Reverts if the expected amount of tokens are not returned from `stakingContract`
    * @param amount deposit tokens to reinvest
    */
  function _reinvest(uint amount) private {
    stakingContract.deposit(PID, 0);

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
    
    uint depositTokenAmount = amount.sub(devFee).sub(adminFee).sub(reinvestFee);
    if (address(swapPairWAVAXTundra) != address(0)) {
      uint amountWavax = DexLibrary.swap(depositTokenAmount, address(rewardToken), address(WAVAX), swapPairWAVAXTundra);
      if (address(swapPairToken) != address(0)) {
        depositTokenAmount = DexLibrary.swap(amountWavax, address(WAVAX), address(depositToken), swapPairToken);
      }
    }
    else if (address(swapPairToken) != address(0)) {
      depositTokenAmount = DexLibrary.swap(depositTokenAmount, address(rewardToken), address(depositToken), swapPairToken);
    }

    _stakeDepositTokens(depositTokenAmount);
    totalDeposits = totalDeposits.add(depositTokenAmount);

    emit Reinvest(totalDeposits, totalSupply);
  }
    
  function _stakeDepositTokens(uint amount) private {
    require(amount > 0, "FrostStrategyForSA::_stakeDepositTokens");
    stakingContract.deposit(PID, amount);
  }

  /**
    * @notice Safely transfer using an anonymosu ERC20 token
    * @dev Requires token to return true on transfer
    * @param token address
    * @param to recipient address
    * @param value amount
    */
  function _safeTransfer(address token, address to, uint256 value) private {
    require(IERC20(token).transfer(to, value), 'DexStrategyV6::TRANSFER_FROM_FAILED');
  }
  
  function checkReward() public override view returns (uint) {
    uint pendingReward = stakingContract.pendingTUNDRA(PID, address(this));
    uint contractBalance = rewardToken.balanceOf(address(this));
    return pendingReward.add(contractBalance);
  }

  /**
   * @notice Estimate recoverable balance after withdraw fee
   * @return deposit tokens after withdraw fee
   */
  function estimateDeployedBalance() external override view returns (uint) {
    (uint depositBalance, ) = stakingContract.userInfo(PID, address(this));
    (,,,, uint withdrawFeeBP) = stakingContract.poolInfo(PID);
    uint withdrawFee = depositBalance.mul(withdrawFeeBP).div(BIPS_DIVISOR);
    return depositBalance.sub(withdrawFee);
  }

  function rescueDeployedFunds(uint minReturnAmountAccepted, bool disableDeposits) external override onlyOwner {
    uint balanceBefore = depositToken.balanceOf(address(this));
    stakingContract.emergencyWithdraw(PID);
    uint balanceAfter = depositToken.balanceOf(address(this));
    require(balanceAfter.sub(balanceBefore) >= minReturnAmountAccepted, "FrostStrategyForSA::rescueDeployedFunds");
    totalDeposits = balanceAfter;
    emit Reinvest(totalDeposits, totalSupply);
    if (DEPOSITS_ENABLED == true && disableDeposits == true) {
      updateDepositsEnabled(false);
    }
  }
}