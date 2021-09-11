// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "../YakStrategy.sol";
import "../interfaces/IGondolaChef.sol";
import "../interfaces/IPair.sol";
import "../interfaces/IGondolaPool.sol";
import "../lib/DexLibrary.sol";

/**
 * @notice StableSwap strategy for Gondola
 */
contract GondolaStrategyForPoolV2 is YakStrategy {
  using SafeMath for uint;

  IGondolaChef public stakingContract;
  IGondolaPool public poolContract;
  IPair private swapPairWAVAXGDL;
  IPair private swapPairToken0;
  IPair private swapPairToken1;

  address private constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;

  uint public PID;
  uint private immutable decimalAdjustment0;
  uint private immutable decimalAdjustment1;

  constructor(
    string memory _name,
    address _depositToken, 
    address _rewardToken, 
    address _stakingContract,
    address _poolContract,
    address _swapPairWAVAXGDL,
    address _swapPairToken0,
    address _swapPairToken1,
    address _timelock,
    uint _pid,
    uint _decimalAdjustment0,
    uint _decimalAdjustment1,
    uint _minTokensToReinvest,
    uint _adminFeeBips,
    uint _devFeeBips,
    uint _reinvestRewardBips
  ) {
    name = _name;
    depositToken = IPair(_depositToken);
    rewardToken = IERC20(_rewardToken);
    stakingContract = IGondolaChef(_stakingContract);
    poolContract = IGondolaPool(_poolContract);
    swapPairWAVAXGDL = IPair(_swapPairWAVAXGDL);
    swapPairToken0 = IPair(_swapPairToken0);
    swapPairToken1 = IPair(_swapPairToken1);
    PID = _pid;
    decimalAdjustment0 = _decimalAdjustment0;
    decimalAdjustment1 = _decimalAdjustment1;
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
    IERC20(poolContract.getToken(0)).approve(address(poolContract), MAX_UINT);
    IERC20(poolContract.getToken(1)).approve(address(poolContract), MAX_UINT);
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
    require(DEPOSITS_ENABLED == true, "GondolaStrategyForPoolV2::_deposit");
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
      require(depositToken.transfer(msg.sender, depositTokenAmount), "GondolaStrategyForPoolV2::withdraw");
      _burn(msg.sender, amount);
      totalDeposits = totalDeposits.sub(depositTokenAmount);
      emit Withdraw(msg.sender, depositTokenAmount);
    }
  }

  function _withdrawDepositTokens(uint amount) private {
    require(amount > 0, "GondolaStrategyForPoolV2::_withdrawDepositTokens");
    stakingContract.withdraw(PID, amount);
  }

  function reinvest() external override onlyEOA {
    uint unclaimedRewards = checkReward();
    require(unclaimedRewards >= MIN_TOKENS_TO_REINVEST, "GondolaStrategyForPoolV2::reinvest");
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
      require(rewardToken.transfer(devAddr, devFee), "GondolaStrategyForPoolV2::_reinvest, dev");
    }

    uint adminFee = amount.mul(ADMIN_FEE_BIPS).div(BIPS_DIVISOR);
    if (adminFee > 0) {
      require(rewardToken.transfer(owner(), adminFee), "GondolaStrategyForPoolV2::_reinvest, admin");
    }

    uint reinvestFee = amount.mul(REINVEST_REWARD_BIPS).div(BIPS_DIVISOR);
    if (reinvestFee > 0) {
      require(rewardToken.transfer(msg.sender, reinvestFee), "GondolaStrategyForPoolV2::_reinvest, reward");
    }

    uint depositTokenAmount = _convertRewardTokensToDepositTokens(
      amount.sub(devFee).sub(adminFee).sub(reinvestFee)
    );

    _stakeDepositTokens(depositTokenAmount);
    totalDeposits = totalDeposits.add(depositTokenAmount);

    emit Reinvest(totalDeposits, totalSupply);
  }
    
  function _stakeDepositTokens(uint amount) private {
    require(amount > 0, "GondolaStrategyForPoolV2::_stakeDepositTokens");
    stakingContract.deposit(PID, amount);
  }

  function checkReward() public override view returns (uint) {
    uint pendingReward = stakingContract.pendingGondola(PID, address(this));
    uint contractBalance = rewardToken.balanceOf(address(this));
    return pendingReward.add(contractBalance);
  }

  /**
    * @notice Converts reward tokens to deposit tokens
    * @dev No price checks enabled
    * @return deposit tokens received
    */
  function _convertRewardTokensToDepositTokens(uint amount) private returns (uint) {
    require(amount > 0, "GondolaStrategyForPoolV2::_convertRewardTokensToDepositTokens");

    uint convertedAmountWAVAX = DexLibrary.swap(
      amount,
      address(rewardToken), address(WAVAX),
      swapPairWAVAXGDL
    );

    uint[] memory liquidityAmounts = new uint[](2);

    // find route for bonus token
    if (poolContract.getTokenBalance(0).mul(decimalAdjustment0) < poolContract.getTokenBalance(1).mul(decimalAdjustment1)) {
      // convert to 0
      liquidityAmounts[0] = DexLibrary.swap(
        convertedAmountWAVAX,
        address(WAVAX), poolContract.getToken(0),
        swapPairToken0
      );
    }
    else {
      // convert to 1
      liquidityAmounts[1] = DexLibrary.swap(
        convertedAmountWAVAX,
        address(WAVAX), poolContract.getToken(1),
        swapPairToken1
      );
    }

    uint liquidity = poolContract.addLiquidity(liquidityAmounts, 0, block.timestamp);
    return liquidity;
  }

  /**
   * @notice Estimate recoverable balance
   * @return deposit tokens
   */
  function estimateDeployedBalance() external override view returns (uint) {
    (uint depositBalance, ) = stakingContract.userInfo(PID, address(this));
    return depositBalance;
  }

  function rescueDeployedFunds(uint minReturnAmountAccepted, bool disableDeposits) external override onlyOwner {
    uint balanceBefore = depositToken.balanceOf(address(this));
    stakingContract.emergencyWithdraw(PID);
    uint balanceAfter = depositToken.balanceOf(address(this));
    require(balanceAfter.sub(balanceBefore) >= minReturnAmountAccepted, "GondolaStrategyForPoolV2::rescueDeployedFunds");
    totalDeposits = balanceAfter;
    emit Reinvest(totalDeposits, totalSupply);
    if (DEPOSITS_ENABLED == true && disableDeposits == true) {
      updateDepositsEnabled(false);
    }
  }
}