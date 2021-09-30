// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "../YakStrategy.sol";
import "../interfaces/IPenguinChef.sol";
import "../interfaces/IRouter.sol";
import "../interfaces/IPair.sol";

/**
 * @notice Token1 strategy for Penguin Igloos
 */
contract PenguinStrategyForLPb is YakStrategy {
  using SafeMath for uint;

  IRouter public router;
  IPenguinChef public stakingContract;
  address private constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;

  uint public PID;

  constructor(
    string memory _name,
    address _depositToken, 
    address _rewardToken, 
    address _stakingContract,
    address _router,
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
    stakingContract = IPenguinChef(_stakingContract);
    router = IRouter(_router);
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
    rewardToken.approve(address(router), MAX_UINT);
    IERC20(IPair(address(depositToken)).token0()).approve(address(router), MAX_UINT);
    IERC20(IPair(address(depositToken)).token1()).approve(address(router), MAX_UINT);
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
    require(DEPOSITS_ENABLED == true, "PenguinStrategyForLP::_deposit");
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
      require(depositToken.transfer(msg.sender, depositTokenAmount.sub(withdrawFee)), "PenguinStrategyForLP::withdraw");
      _burn(msg.sender, amount);
      totalDeposits = totalDeposits.sub(depositTokenAmount);
      emit Withdraw(msg.sender, depositTokenAmount);
    }
  }

  function _withdrawDepositTokens(uint amount) private {
    require(amount > 0, "PenguinStrategyForLP::_withdrawDepositTokens");
    stakingContract.withdraw(PID, amount);
  }

  function reinvest() external override onlyEOA {
    uint unclaimedRewards = checkReward();
    require(unclaimedRewards >= MIN_TOKENS_TO_REINVEST, "PenguinStrategyForLP::reinvest");
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
      require(rewardToken.transfer(devAddr, devFee), "PenguinStrategyForLP::_reinvest, dev");
    }

    uint adminFee = amount.mul(ADMIN_FEE_BIPS).div(BIPS_DIVISOR);
    if (adminFee > 0) {
      require(rewardToken.transfer(owner(), adminFee), "PenguinStrategyForLP::_reinvest, admin");
    }

    uint reinvestFee = amount.mul(REINVEST_REWARD_BIPS).div(BIPS_DIVISOR);
    if (reinvestFee > 0) {
      require(rewardToken.transfer(msg.sender, reinvestFee), "PenguinStrategyForLP::_reinvest, reward");
    }

    uint depositTokenAmount = _convertRewardTokensToDepositTokens(
      amount.sub(devFee).sub(adminFee).sub(reinvestFee)
    );

    _stakeDepositTokens(depositTokenAmount);
    totalDeposits = totalDeposits.add(depositTokenAmount);

    emit Reinvest(totalDeposits, totalSupply);
  }
    
  function _stakeDepositTokens(uint amount) private {
    require(amount > 0, "PenguinStrategyForLP::_stakeDepositTokens");
    stakingContract.deposit(PID, amount);
  }

  function checkReward() public override view returns (uint) {
    uint pendingReward = stakingContract.pendingPEFI(PID, address(this));
    uint contractBalance = rewardToken.balanceOf(address(this));
    return pendingReward.add(contractBalance);
  }

  /**
    * @notice Converts reward tokens to deposit tokens
    * @dev Always converts through router; there are no price checks enabled
    * @return deposit tokens received
    */
  function _convertRewardTokensToDepositTokens(uint amount) private returns (uint) {
    uint amountIn = amount.div(2);
    require(amountIn > 0, "PenguinStrategyForLP::_convertRewardTokensToDepositTokens");

    // swap to token0
    uint path0Length = 2;
    address[] memory path0 = new address[](path0Length);
    path0[0] = address(rewardToken);
    path0[1] = IPair(address(depositToken)).token0();

    uint amountOutToken0 = amountIn;
    if (path0[0] != path0[path0Length - 1]) {
      uint[] memory amountsOutToken0 = router.getAmountsOut(amountIn, path0);
      amountOutToken0 = amountsOutToken0[amountsOutToken0.length - 1];
      router.swapExactTokensForTokens(amountIn, amountOutToken0, path0, address(this), block.timestamp);
    }

    // swap to token1
    uint path1Length = 3;
    address[] memory path1 = new address[](path1Length);
    path1[0] = path0[0];
    path1[1] = WAVAX;
    path1[2] = IPair(address(depositToken)).token1();

    uint amountOutToken1 = amountIn;
    if (path1[0] != path1[path1Length - 1]) {
      uint[] memory amountsOutToken1 = router.getAmountsOut(amountIn, path1);
      amountOutToken1 = amountsOutToken1[amountsOutToken1.length - 1];
      router.swapExactTokensForTokens(amountIn, amountOutToken1, path1, address(this), block.timestamp);
    }

    (,,uint liquidity) = router.addLiquidity(
      path0[path0Length - 1], path1[path1Length - 1],
      amountOutToken0, amountOutToken1,
      0, 0,
      address(this),
      block.timestamp
    );

    return liquidity;
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
    require(balanceAfter.sub(balanceBefore) >= minReturnAmountAccepted, "PenguinStrategyForLP::rescueDeployedFunds");
    totalDeposits = balanceAfter;
    emit Reinvest(totalDeposits, totalSupply);
    if (DEPOSITS_ENABLED == true && disableDeposits == true) {
      updateDepositsEnabled(false);
    }
  }
}