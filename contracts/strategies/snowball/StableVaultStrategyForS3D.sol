// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "../YakStrategy.sol";
import "../interfaces/IGauge.sol";
import "../interfaces/IRouter.sol";
import "../interfaces/IPair.sol";
import "../interfaces/IGondolaPool.sol";

/**
 * @notice StableSwap strategy
 */
contract StableVaultStrategyForS3D is YakStrategy {
  using SafeMath for uint;

  IRouter public router;
  IGauge public stakingContract;
  IGondolaPool public poolContract;

  address private constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
  address private constant USDT = 0xde3A24028580884448a5397872046a019649b084;

  constructor(
    string memory _name,
    address _depositToken, 
    address _rewardToken, 
    address _stakingContract,
    address _poolContract,
    address _router,
    address _timelock,
    uint _minTokensToReinvest,
    uint _adminFeeBips,
    uint _devFeeBips,
    uint _reinvestRewardBips
  ) {
    name = _name;
    depositToken = IPair(_depositToken);
    rewardToken = IERC20(_rewardToken);
    stakingContract = IGauge(_stakingContract);
    router = IRouter(_router);
    poolContract = IGondolaPool(_poolContract);
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
    IERC20(USDT).approve(address(poolContract), MAX_UINT);
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
    require(DEPOSITS_ENABLED == true, "StableVaultStrategy::_deposit");
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
      require(depositToken.transfer(msg.sender, depositTokenAmount), "StableVaultStrategy::withdraw");
      _burn(msg.sender, amount);
      totalDeposits = totalDeposits.sub(depositTokenAmount);
      emit Withdraw(msg.sender, depositTokenAmount);
    }
  }

  function _withdrawDepositTokens(uint amount) private {
    require(amount > 0, "StableVaultStrategy::_withdrawDepositTokens");
    stakingContract.withdraw(amount);
  }

  function reinvest() external override onlyEOA {
    uint unclaimedRewards = checkReward();
    require(unclaimedRewards >= MIN_TOKENS_TO_REINVEST, "StableVaultStrategy::reinvest");
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
      require(rewardToken.transfer(devAddr, devFee), "StableVaultStrategy::_reinvest, dev");
    }

    uint adminFee = amount.mul(ADMIN_FEE_BIPS).div(BIPS_DIVISOR);
    if (adminFee > 0) {
      require(rewardToken.transfer(owner(), adminFee), "StableVaultStrategy::_reinvest, admin");
    }

    uint reinvestFee = amount.mul(REINVEST_REWARD_BIPS).div(BIPS_DIVISOR);
    if (reinvestFee > 0) {
      require(rewardToken.transfer(msg.sender, reinvestFee), "StableVaultStrategy::_reinvest, reward");
    }

    uint depositTokenAmount = _convertRewardTokensToDepositTokens(
      amount.sub(devFee).sub(adminFee).sub(reinvestFee)
    );

    _stakeDepositTokens(depositTokenAmount);
    totalDeposits = totalDeposits.add(depositTokenAmount);

    emit Reinvest(totalDeposits, totalSupply);
  }
    
  function _stakeDepositTokens(uint amount) private {
    require(amount > 0, "StableVaultStrategy::_stakeDepositTokens");
    stakingContract.deposit(amount);
  }

  function checkReward() public override view returns (uint) {
    uint pendingReward = stakingContract.earned(address(this));
    return pendingReward;
    // uint contractBalance = rewardToken.balanceOf(address(this));
    // return pendingReward.add(contractBalance);
  }

  /**
    * @notice Converts reward tokens to deposit tokens
    * @dev Always converts through router; there are no price checks enabled
    * @return deposit tokens received
    */
  function _convertRewardTokensToDepositTokens(uint amount) private returns (uint) {
    require(amount > 0, "StableVaultStrategy::_convertRewardTokensToDepositTokens");

    // convert to USDT
    address[] memory path = new address[](3);
    path[0] = address(rewardToken);
    path[1] = WAVAX;
    path[2] = USDT;
    uint[] memory amountsOutToken = router.getAmountsOut(amount, path);
    uint amountOutToken = amountsOutToken[amountsOutToken.length - 1];
    router.swapExactTokensForTokens(amount, amountOutToken, path, address(this), block.timestamp);
    
    uint[] memory liquidityAmounts = new uint[](3);
    liquidityAmounts[0] = amountOutToken;

    uint liquidity = poolContract.addLiquidity(liquidityAmounts, 0, block.timestamp);
    return liquidity;
  }

  /**
   * @notice Estimate recoverable balance
   * @return deposit tokens
   */
  function estimateDeployedBalance() external override view returns (uint) {
    return stakingContract.balanceOf(address(this));
  }

  function rescueDeployedFunds(uint minReturnAmountAccepted, bool disableDeposits) external override onlyOwner {
    uint balanceBefore = depositToken.balanceOf(address(this));
    stakingContract.exit();
    uint balanceAfter = depositToken.balanceOf(address(this));
    require(balanceAfter.sub(balanceBefore) >= minReturnAmountAccepted, "StableVaultStrategy::rescueDeployedFunds");
    totalDeposits = balanceAfter;
    emit Reinvest(totalDeposits, totalSupply);
    if (DEPOSITS_ENABLED == true && disableDeposits == true) {
      updateDepositsEnabled(false);
    }
  }
}