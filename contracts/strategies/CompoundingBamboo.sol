// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "../YakStrategy.sol";
import "../interfaces/IBambooChef.sol";
import "../interfaces/IBambooBar.sol";
import "../interfaces/IRouter.sol";
import "../interfaces/IPair.sol";

/**
 * @notice Single asset strategy for BAMBOO
 */
contract CompoundingBamboo is YakStrategy {
  using SafeMath for uint;

  IRouter public router;
  IBambooChef public stakingContract;
  IBambooBar public conversionContract;
  IERC20 public sBamboo;

  uint public PID;

  constructor(
    string memory _name,
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
    depositToken = IPair(_depositToken);
    rewardToken = IERC20(_rewardToken);
    stakingContract = IBambooChef(_stakingContract);
    conversionContract = IBambooBar(_conversionContract);
    sBamboo = IERC20(_conversionContract);
    PID = _pid;
    devAddr = 0xD15E8b816F040fB0d7495ebA36C16Cf0f33c049c;

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
    sBamboo.approve(address(stakingContract), MAX_UINT);
  }

  /**
   * @notice Deposit tokens to receive receipt tokens
   * @param amount Amount of tokens to deposit
   */
  function deposit(uint amount) external override {
    _deposit(depositToken, msg.sender, amount);
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
    _deposit(depositToken, msg.sender, amount);
  }

  function depositFor(address account, uint amount) external override {
      _deposit(depositToken, account, amount);
  }

  function depositSBamboo(uint amount) external {
    _deposit(sBamboo, msg.sender, amount);
  }

  function depositSBambooWithPermit(uint amount, uint deadline, uint8 v, bytes32 r, bytes32 s) external {
    sBamboo.permit(msg.sender, address(this), amount, deadline, v, r, s);
    _deposit(sBamboo, msg.sender, amount);
  }

  function depositSBambooFor(address account, uint amount) external {
      _deposit(sBamboo, account, amount);
  }

  /**
   * @notice Deposit Bamboo or sBamboo
   * @param token address
   * @param account address
   * @param amount token amount
   */
  function _deposit(address token, address account, uint amount) internal {
    require(DEPOSITS_ENABLED == true, "CompoundingBamboo::_deposit");
    require(token == address(depositToken) || token == address(sBamboo), "CompoundingBamboo::_deposit, token not accepted");
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
    else if (token == address(sBamboo)) {
      require(sBamboo.transferFrom(msg.sender, address(this), amount));
      depositTokenAmount = _getBambooForSBamboo(amount);
      _stakeSBamboo(amount);
    }

    _mint(account, getSharesForDepositTokens(depositTokenAmount));
    totalDeposits = totalDeposits.add(depositTokenAmount);
    emit Deposit(account, depositTokenAmount);
  }

  function withdraw(uint amount) external override {
    uint depositTokenAmount = getDepositTokensForShares(amount);
    if (depositTokenAmount > 0) {
      _withdrawDepositTokens(depositTokenAmount);
      require(depositToken.transfer(msg.sender, depositTokenAmount), "CompoundingBamboo::withdraw");
      _burn(msg.sender, amount);
      totalDeposits = totalDeposits.sub(depositTokenAmount);
      emit Withdraw(msg.sender, depositTokenAmount);
    }
  }

  /**
   * @notice Withdraw Bamboo
   * @param amount deposit tokens
   */
  function _withdrawDepositTokens(uint amount) private {
    require(amount > 0, "CompoundingBamboo::_withdrawDepositTokens");
    uint sBambooAmount = _getSBambooForBamboo(amount);
    stakingContract.withdraw(PID, sBambooAmount);
    conversionContract.leave(sBambooAmount);
  }

  function reinvest() external override onlyEOA {
    uint unclaimedRewards = checkReward();
    require(unclaimedRewards >= MIN_TOKENS_TO_REINVEST, "CompoundingBamboo::reinvest");
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
      require(rewardToken.transfer(devAddr, devFee), "CompoundingBamboo::_reinvest, dev");
    }

    uint adminFee = amount.mul(ADMIN_FEE_BIPS).div(BIPS_DIVISOR);
    if (adminFee > 0) {
      require(rewardToken.transfer(owner(), adminFee), "CompoundingBamboo::_reinvest, admin");
    }

    uint reinvestFee = amount.mul(REINVEST_REWARD_BIPS).div(BIPS_DIVISOR);
    if (reinvestFee > 0) {
      require(rewardToken.transfer(msg.sender, reinvestFee), "CompoundingBamboo::_reinvest, reward");
    }

    uint depositTokenAmount = amount.sub(devFee).sub(adminFee).sub(reinvestFee);
    _stakeDepositTokens(depositTokenAmount);
    totalDeposits = totalDeposits.add(depositTokenAmount);

    emit Reinvest(totalDeposits, totalSupply);
  }
  
  /**
   * @notice Convert and stake Bamboo
   * @param amount deposit tokens
   */
  function _stakeDepositTokens(uint amount) private {
    uint sBambooAmount = _getSBambooForBamboo(amount);
    _convertBambooToSBamboo(amount);
    _stakeSBamboo(sBambooAmount);
  }

  /**
   * @notice Convert bamboo to sBamboo
   * @param amount deposit token
   */
  function _convertBambooToSBamboo(uint amount) private {
    require(amount > 0, "CompoundingBamboo::_convertBambooToSBamboo");
    conversionContract.enter(amount);
  }

  /**
   * @notice Stake sBamboo
   * @param amount sBamboo
   */
  function _stakeSBamboo(uint amount) private {
    require(amount > 0, "CompoundingBamboo::_stakeSBamboo");
    stakingContract.deposit(PID, amount);
  }

  function checkReward() public override view returns (uint) {
    uint pendingReward = stakingContract.pendingBamboo(PID, address(this));
    uint contractBalance = rewardToken.balanceOf(address(this));
    return pendingReward.add(contractBalance);
  }

  /**
   * @notice Estimate recoverable balance
   * @return deposit tokens
   */
  function estimateDeployedBalance() external override view returns (uint) {
    (uint depositBalance, ) = stakingContract.userInfo(PID, address(this));
    return _getBambooForSBamboo(depositBalance);
  }

  /**
   * @notice Conversion rate for Bamboo to sBamboo
   * @param amount Bamboo tokens
   * @return sBamboo shares
   */
  function _getSBambooForBamboo(uint amount) private view returns (uint) {
    uint bambooBalance = depositToken.balanceOf(address(conversionContract));
    uint sBambooShares = sBamboo.totalSupply();
    if (bambooBalance.mul(sBambooShares) == 0) {
      return amount;
    }
    return amount.mul(sBambooShares).div(bambooBalance);
  }

  /**
   * @notice Conversion rate for sBamboo to Bamboo
   * @param amount sBamboo shares
   * @return Bamboo tokens
   */
  function _getBambooForSBamboo(uint amount) private view returns (uint) {
    uint bambooBalance = depositToken.balanceOf(address(conversionContract));
    uint sBambooShares = sBamboo.totalSupply();
    if (bambooBalance.mul(sBambooShares) == 0) {
      return amount;
    }
    return amount.mul(bambooBalance).div(sBambooShares);
  }

  function rescueDeployedFunds(uint minReturnAmountAccepted, bool disableDeposits) external override onlyOwner {
    uint balanceBefore = depositToken.balanceOf(address(this));
    stakingContract.emergencyWithdraw(PID);
    conversionContract.leave(sBamboo.balanceOf(address(this)));
    uint balanceAfter = depositToken.balanceOf(address(this));
    require(balanceAfter.sub(balanceBefore) >= minReturnAmountAccepted, "CompoundingBamboo::rescueDeployedFunds");
    totalDeposits = balanceAfter;
    emit Reinvest(totalDeposits, totalSupply);
    if (DEPOSITS_ENABLED == true && disableDeposits == true) {
      updateDepositsEnabled(false);
    }
  }
}