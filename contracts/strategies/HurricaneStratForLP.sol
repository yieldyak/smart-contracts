// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "../YakStrategy.sol";
import "../interfaces/IHurricaneRouter.sol";
import "../interfaces/IHurricaneFactory.sol";
import "../interfaces/IHurricaneMasterChief.sol";
import "../lib/SafeMath.sol";
import "../lib/DexLibrary.sol";

/**
 * @notice LP strategy for HurricaneSwap
 */
contract HurricaneStratForLP is YakStrategy {

  using SafeMath for uint;
  using SafeMath for uint256;
  IHurricaneMasterChief public stakingContract;
  IHurricaneRouter public router;
  address[] route1;
  address[] route0;
  uint public PID;


  constructor(
    string memory _name,
    address _depositToken, 
    address _rewardToken, 
    address _stakingContract,
    address _router,
    address _timelock,
    address[] memory _route0,
    address[] memory _route1,
    uint _pid,
    uint _minTokensToReinvest,
    uint _adminFeeBips,
    uint _devFeeBips,
    uint _reinvestRewardBips
  ) {
    name = _name;
    depositToken = IERC20(_depositToken);
    rewardToken = IERC20(_rewardToken);
    stakingContract = IHurricaneMasterChief(_stakingContract);
    PID = _pid;
    devAddr = msg.sender;
    router = IHurricaneRouter(_router);
    // Perform checks on the routes
    setRoutes(_route0, _route1);
    setAllowances();
    updateMinTokensToReinvest(_minTokensToReinvest);
    updateAdminFee(_adminFeeBips);
    updateDevFee(_devFeeBips);
    updateReinvestReward(_reinvestRewardBips);
    updateDepositsEnabled(true);
    transferOwnership(_timelock);
    

    emit Reinvest(0, 0);
  }

  function setRoutes(address[] memory _route0, address[] memory _route1) external onlyOwner {
    require((_route0.length > 1) && (_route1.length > 1), "a route is too short");
    require(_route0[0] == _route1[0], "routes do not start at the same token");
    require(_route0[0] == address(rewardToken), "routes do not start at rewardToken");
    (route0, route1) = _route0[_route0.length-1] < _route1[_route1.length-1] ? (_route0, _route1) : (_route1, _route0);

  }


  /**
   * @notice Approve tokens for use in Strategy
   * @dev Restricted to avoid griefing attacks
   */
  function setAllowances() public override onlyOwner {
    depositToken.approve(address(stakingContract), MAX_UINT);
    rewardToken.approve(address(router), MAX_UINT);
    IPair depositPair = IPair(address(depositToken));
    IERC20(depositPair.token0()).approve(address(router), MAX_UINT);
    IERC20(depositPair.token1()).approve(address(router), MAX_UINT);
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
    require(DEPOSITS_ENABLED == true, "HurricaneStrategyForLP::_deposit");
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

  function _safeTransfer(address token, address to, uint256 value) private {
    require(IERC20(token).transfer(to, value), "HurricaneStrategyForLP::withdraw");
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

  function _withdrawDepositTokens(uint amount) private {
    require(amount > 0, "HurricaneStrategyForLP::_withdrawDepositTokens");
    stakingContract.withdraw(PID, amount);
  }

  function reinvest() external override onlyEOA {
    uint unclaimedRewards = checkReward();
    require(unclaimedRewards >= MIN_TOKENS_TO_REINVEST, "HurricaneStrategyForLP::reinvest");
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
      require(rewardToken.transfer(devAddr, devFee), "HurricaneStrategyForLP::_reinvest, dev");
    }

    uint adminFee = amount.mul(ADMIN_FEE_BIPS).div(BIPS_DIVISOR);
    if (adminFee > 0) {
      require(rewardToken.transfer(owner(), adminFee), "HurricaneStrategyForLP::_reinvest, admin");
    }

    uint reinvestFee = amount.mul(REINVEST_REWARD_BIPS).div(BIPS_DIVISOR);
    if (reinvestFee > 0) {
      require(rewardToken.transfer(msg.sender, reinvestFee), "HurricaneStrategyForLP::_reinvest, reward");
    }

    uint depositTokenAmount = _convertRewardTokensToDepositTokens(
      amount.sub(devFee).sub(adminFee).sub(reinvestFee)
    );

    _stakeDepositTokens(depositTokenAmount);
    totalDeposits = totalDeposits.add(depositTokenAmount);

    emit Reinvest(totalDeposits, totalSupply);
  }
    

  function _stakeDepositTokens(uint amount) private {
    require(amount > 0, "HurricaneStrategyForLP::amount=0");
    stakingContract.deposit(PID, amount);
  }

  function checkReward() public override view returns (uint) {
    (uint256 pendingAmounts,) = stakingContract.pending(PID, address(this));
    return pendingAmounts;
  }

    function getFinalAmountOut(address factory, uint amountIn, address[] memory path) internal view returns (uint amount) {
        require(path.length >= 2, 'getFinalAmountOut: INVALID_PATH');
        amount = amountIn;
        for (uint i; i < path.length - 1; i++) {
            (uint reserveIn, uint reserveOut) = getReserves(factory, path[i], path[i + 1]);
            amount = DexLibrary.getAmountOut(amount, reserveIn, reserveOut);
        }
        return amount;
    }

    function getReserves(address factory, address tokenA, address tokenB) internal view returns (uint reserveA, uint reserveB) {
        (address token0,) = DexLibrary.sortTokens(tokenA, tokenB);
        address pair_address = IHurricaneFactory(factory).getPair(tokenA, tokenB); // FUNCTION IS NOT YAK
        (uint reserve0, uint reserve1,) = IPair(pair_address).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

  /**
    * @notice Converts reward tokens to deposit tokens
    * @dev Always converts through router; there are no price checks enabled
    * @return deposit tokens received
    */
  function _convertRewardTokensToDepositTokens(uint amount) private returns (uint) {
    uint amountIn = amount.div(2);
    require(amountIn > 0, "HurricaneStrategyForLP::!amounIn=0");

    uint256 amountOutToken0 = getFinalAmountOut(router.factory(), amountIn, route0);
    router.swapExactTokensForTokens(
        amountIn, amountOutToken0, route0,
        address(this), block.timestamp
    );

    uint256 amountOutToken1 = getFinalAmountOut(router.factory(), amountIn, route1);
    router.swapExactTokensForTokens(
        amountIn, amountOutToken1, route1,
        address(this), block.timestamp
    );

    (,,uint liquidity) = router.addLiquidity(
      route0[route0.length - 1], route1[route1.length - 1],
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
    (uint depositBalance,,) = stakingContract.userInfo(PID, address(this));
    return depositBalance;
  }

  function emergencyWithdraw() external onlyOwner {
    stakingContract.emergencyWithdraw(PID);
    totalDeposits = 0;
  }

  function rescueDeployedFunds(uint minReturnAmountAccepted, bool disableDeposits) external override onlyOwner {
    uint balanceBefore = depositToken.balanceOf(address(this));
    stakingContract.emergencyWithdraw(PID);
    uint balanceAfter = depositToken.balanceOf(address(this));
    require(balanceAfter.sub(balanceBefore) >= minReturnAmountAccepted, "HurricaneStrategyForLP::rescueDeployedFunds");
    totalDeposits = balanceAfter;
    emit Reinvest(totalDeposits, totalSupply);
    if (DEPOSITS_ENABLED == true && disableDeposits == true) {
      updateDepositsEnabled(false);
    }
  }
}