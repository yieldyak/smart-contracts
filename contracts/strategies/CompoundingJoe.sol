// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "../YakStrategy.sol";
import "../interfaces/IJoeChef.sol";
import "../interfaces/IJoeBar.sol";
import "../interfaces/IRouter.sol";
import "../interfaces/IPair.sol";

/**
 * @notice Single asset strategy for BAMBOO
 */
contract CompoundingJoe is YakStrategy {
  using SafeMath for uint;

  IRouter public router;
  IJoeChef public stakingContract;
  IJoeBar public conversionContract;
  IERC20 public xJoe;

  uint public PID;

  constructor(
    string memory _name,
    string memory _symbol,
    address _depositToken, 
    address _rewardToken, 
    address _stakingContract,
    address _conversionContract,
    address _timelock,
    uint _pid,
    uint _minTokensToReinvest,
    uint _adminFeeBips,
    uint _devFeeBips,
    uint _reinvestRewardBips
  ) {
    name = _name;
    symbol = _symbol;
    depositToken = IPair(_depositToken);
    rewardToken = IERC20(_rewardToken);
    stakingContract = IJoeChef(_stakingContract);
    conversionContract = IJoeBar(_conversionContract);
    xJoe = IERC20(_conversionContract);
    PID = _pid;
    devAddr = 0xcEf537d5773e321DD4Bc61D0e02B7BD7c46685F6;

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
    depositToken.approve(address(conversionContract), MAX_UINT);
    xJoe.approve(address(stakingContract), MAX_UINT);
  }

  /**
   * @notice Deposit tokens to receive receipt tokens
   * @param amount Amount of tokens to deposit
   */
  function deposit(uint amount) external override {
    _deposit(address(depositToken), msg.sender, amount);
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
    _deposit(address(depositToken), msg.sender, amount);
  }

  function depositFor(address account, uint amount) external override {
      _deposit(address(depositToken), account, amount);
  }

  function depositXJoe(uint amount) external {
    _deposit(address(xJoe), msg.sender, amount);
  }

  function depositXJoeWithPermit(uint amount, uint deadline, uint8 v, bytes32 r, bytes32 s) external {
    xJoe.permit(msg.sender, address(this), amount, deadline, v, r, s);
    _deposit(address(xJoe), msg.sender, amount);
  }

  function depositXJoeFor(address account, uint amount) external {
      _deposit(address(xJoe), account, amount);
  }

  /**
   * @notice Deposit Joe or xJoe
   * @param token address
   * @param account address
   * @param amount token amount
   */
  function _deposit(address token, address account, uint amount) internal {
    require(DEPOSITS_ENABLED == true, "CompoundingJoe::_deposit");
    require(token == address(depositToken) || token == address(xJoe), "CompoundingJoe::_deposit, token not accepted");
    if (MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST > 0) {
        uint unclaimedRewards = checkReward();
        if (unclaimedRewards > MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST) {
            _reinvest(unclaimedRewards);
        }
    }

    uint depositTokenAmount;
    if (token == address(depositToken)) {
      require(depositToken.transferFrom(msg.sender, address(this), amount));
      depositTokenAmount = amount;
      _stakeDepositTokens(amount);
    }
    else if (token == address(xJoe)) {
      require(xJoe.transferFrom(msg.sender, address(this), amount));
      depositTokenAmount = _getJoeForXJoe(amount);
      _stakeXJoe(amount);
    }

    _mint(account, getSharesForDepositTokens(depositTokenAmount));
    totalDeposits = totalDeposits.add(depositTokenAmount);
    emit Deposit(account, depositTokenAmount);
  }

  function withdraw(uint amount) external override {
    uint depositTokenAmount = getDepositTokensForShares(amount);
    if (depositTokenAmount > 0) {
      _withdrawDepositTokens(depositTokenAmount);
      require(depositToken.transfer(msg.sender, depositTokenAmount), "CompoundingJoe::withdraw");
      _burn(msg.sender, amount);
      totalDeposits = totalDeposits.sub(depositTokenAmount);
      emit Withdraw(msg.sender, depositTokenAmount);
    }
  }

  /**
   * @notice Withdraw Joe
   * @param amount deposit tokens
   */
  function _withdrawDepositTokens(uint amount) private {
    require(amount > 0, "CompoundingJoe::_withdrawDepositTokens");
    uint xJoeAmount = _getXJoeForJoe(amount);
    stakingContract.withdraw(PID, xJoeAmount);
    conversionContract.leave(xJoeAmount);
  }

  function reinvest() external override onlyEOA {
    uint unclaimedRewards = checkReward();
    require(unclaimedRewards >= MIN_TOKENS_TO_REINVEST, "CompoundingJoe::reinvest");
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
      require(rewardToken.transfer(devAddr, devFee), "CompoundingJoe::_reinvest, dev");
    }

    uint adminFee = amount.mul(ADMIN_FEE_BIPS).div(BIPS_DIVISOR);
    if (adminFee > 0) {
      require(rewardToken.transfer(owner(), adminFee), "CompoundingJoe::_reinvest, admin");
    }

    uint reinvestFee = amount.mul(REINVEST_REWARD_BIPS).div(BIPS_DIVISOR);
    if (reinvestFee > 0) {
      require(rewardToken.transfer(msg.sender, reinvestFee), "CompoundingJoe::_reinvest, reward");
    }

    uint depositTokenAmount = amount.sub(devFee).sub(adminFee).sub(reinvestFee);
    _stakeDepositTokens(depositTokenAmount);
    totalDeposits = totalDeposits.add(depositTokenAmount);

    emit Reinvest(totalDeposits, totalSupply);
  }
  
  /**
   * @notice Convert and stake Joe
   * @param amount deposit tokens
   */
  function _stakeDepositTokens(uint amount) private {
    uint xJoeAmount = _getXJoeForJoe(amount);
    _convertJoeToXJoe(amount);
    _stakeXJoe(xJoeAmount);
  }

  /**
   * @notice Convert joe to xJoe
   * @param amount deposit token
   */
  function _convertJoeToXJoe(uint amount) private {
    require(amount > 0, "CompoundingJoe::_convertJoeToXJoe");
    conversionContract.enter(amount);
  }

  /**
   * @notice Stake xJoe
   * @param amount xJoe
   */
  function _stakeXJoe(uint amount) private {
    require(amount > 0, "CompoundingJoe::_stakeXJoe");
    stakingContract.deposit(PID, amount);
  }

  function checkReward() public override view returns (uint) {
    (uint pendingReward, , , ) = stakingContract.pendingTokens(PID, address(this));
    uint contractBalance = rewardToken.balanceOf(address(this));
    return pendingReward.add(contractBalance);
  }

  /**
   * @notice Estimate recoverable balance
   * @return deposit tokens
   */
  function estimateDeployedBalance() external override view returns (uint) {
    (uint depositBalance, ) = stakingContract.userInfo(PID, address(this));
    return _getJoeForXJoe(depositBalance);
  }

  /**
   * @notice Conversion rate for Joe to xJoe
   * @param amount Joe tokens
   * @return xJoe shares
   */
  function _getXJoeForJoe(uint amount) private view returns (uint) {
    uint joeBalance = depositToken.balanceOf(address(conversionContract));
    uint xJoeShares = xJoe.totalSupply();
    if (joeBalance.mul(xJoeShares) == 0) {
      return amount;
    }
    return amount.mul(xJoeShares).div(joeBalance);
  }

  /**
   * @notice Conversion rate for xJoe to Joe
   * @param amount xJoe shares
   * @return Joe tokens
   */
  function _getJoeForXJoe(uint amount) private view returns (uint) {
    uint joeBalance = depositToken.balanceOf(address(conversionContract));
    uint xJoeShares = xJoe.totalSupply();
    if (joeBalance.mul(xJoeShares) == 0) {
      return amount;
    }
    return amount.mul(joeBalance).div(xJoeShares);
  }

  function rescueDeployedFunds(uint minReturnAmountAccepted, bool disableDeposits) external override onlyOwner {
    uint balanceBefore = depositToken.balanceOf(address(this));
    stakingContract.emergencyWithdraw(PID);
    conversionContract.leave(xJoe.balanceOf(address(this)));
    uint balanceAfter = depositToken.balanceOf(address(this));
    require(balanceAfter.sub(balanceBefore) >= minReturnAmountAccepted, "CompoundingJoe::rescueDeployedFunds");
    totalDeposits = balanceAfter;
    emit Reinvest(totalDeposits, totalSupply);
    if (DEPOSITS_ENABLED == true && disableDeposits == true) {
      updateDepositsEnabled(false);
    }
  }
}