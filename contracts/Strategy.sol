//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

// import "hardhat/console.sol";
import "./lib/SafeMath.sol";
import "./interfaces/IStakingRewards.sol";
// import "./interfaces/IPangolinERC20.sol";
import "./interfaces/IPangolinRouter.sol";
import "./interfaces/IPangolinPair.sol";
import "./interfaces/IERC20.sol";
import "./lib/Ownable.sol";

contract Strategy is Ownable {
  using SafeMath for uint256;

  string public name = "Snowball: PGL AVAX-ETH";
  string public symbol = "SNOW";
  uint8 public constant decimals = 18;
  uint256 public totalSupply = 0;
  
  mapping (address => mapping (address => uint256)) internal allowances;
  mapping (address => uint256) internal balances;

  uint256 public totalDeposits = 0;

  IPangolinRouter public router;
  IPangolinPair public lpToken;
  IERC20 private token0;
  IERC20 private token1;
  IERC20 public rewardToken;
  IStakingRewards public stakingContract;

  uint256 public MIN_TOKENS_FOR_REINVEST = 20;
  uint256 public REINVEST_FEE_BIPS = 500;
  uint256 public ADMIN_FEE_BIPS = 500;
  uint256 private BIPS_DIVISOR = 10000;

  event Transfer(address indexed from, address indexed to, uint256 value);
  event Approval(address indexed owner, address indexed spender, uint256 value);
  event Recovered(address token, uint256 amount);
  event UpdateAdminFee(uint256 oldValue, uint256 newValue);
  event UpdateMinTokensToReinvest(uint256 oldValue, uint256 newValue);


  constructor(address _lpToken, address _rewardToken, address _stakingContract, address _router) {
    lpToken = IPangolinPair(_lpToken);
    rewardToken = IERC20(_rewardToken);
    stakingContract = IStakingRewards(_stakingContract);
    router = IPangolinRouter(_router);
    token0 = IERC20(lpToken.token0());
    token1 = IERC20(lpToken.token1());

    rewardToken.approve(_router, uint(-1));
    token0.approve(_router, uint(-1));
    token1.approve(_router, uint(-1));
    lpToken.approve(_stakingContract, uint(-1));
  }

  function allowance(address account, address spender) external view returns (uint) {
    return allowances[account][spender];
  }

  function approve(address spender, uint256 amount) external returns (bool) {
    require(spender != address(0), "approve: approve to the zero address");
    allowances[msg.sender][spender] = amount;
    emit Approval(msg.sender, spender, amount);
    return true;
  }

  function balanceOf(address account) external view returns (uint) {
    return balances[account];
  }

  function transfer(address dst, uint256 amount) external returns (bool) {
    _transferTokens(msg.sender, dst, amount);
    return true;
  }

  function transferFrom(address src, address dst, uint256 amount) external returns (bool) {
    address spender = msg.sender;
    uint256 spenderAllowance = allowances[src][spender];

    if (spender != src && spenderAllowance != uint256(-1)) {
      uint256 newAllowance = spenderAllowance.sub(amount, "transferFrom: transfer amount exceeds allowance");
      allowances[src][spender] = newAllowance;

      emit Approval(src, spender, newAllowance);
    }

    _transferTokens(src, dst, amount);
    return true;
  }


  function _transferTokens(address from, address to, uint256 value) internal {
    require(to != address(0), "_transferTokens: cannot transfer to the zero address");

    balances[from] = balances[from].sub(value, "_transferTokens: transfer exceeds from balance");
    balances[to] = balances[to].add(value);
    emit Transfer(from, to, value);
  }

  function _mint(address to, uint256 value) internal {
    totalSupply = totalSupply.add(value);
    balances[to] = balances[to].add(value);
    emit Transfer(address(0), to, value);
  }

  function _burn(address from, uint256 value) internal {
    balances[from] = balances[from].sub(value, "_burn: burn amount exceeds from balance");
    totalSupply = totalSupply.sub(value, "_burn: burn amount exceeds total supply");
    emit Transfer(from, address(0), value);
  }

  /**
   * @notice Deposit LP tokens to receive Snowball tokens
   * @param amount Amount of LP tokens to deposit
   */
  function deposit(uint amount) external {
    _deposit(amount);
  }

  /**
   * @notice Deposit LP tokens to receive Snowball tokens
   * @param amount Amount of LP tokens to deposit
   * @param deadline The time at which to expire the signature
   * @param v The recovery byte of the signature
   * @param r Half of the ECDSA signature pair
   * @param s Half of the ECDSA signature pair
   */
  function depositWithPermit(uint amount, uint deadline, uint8 v, bytes32 r, bytes32 s) external {
    lpToken.permit(msg.sender, address(this), amount, deadline, v, r, s);
    _deposit(amount);
  }

  function _deposit(uint amount) internal {
    require(lpToken.allowance(msg.sender, address(this)) >= amount, "deposit::allowance");
    require(lpToken.transferFrom(msg.sender, address(this), amount), "deposit::transferFrom");
    _stakeLpTokens(amount);
    _mint(msg.sender, getSharesForLPTokens(amount));
  }

  /**
   * @notice Withdraw LP tokens by redeeming Snowball tokens
   * @param amount Amount of Snowball tokens to redeem
   */
  function withdraw(uint amount) external {
    uint lpTokenAmount = getLPTokensForShares(amount);
    if (lpTokenAmount > 0) {
      _withdrawLpTokens(lpTokenAmount);
      require(lpToken.transfer(msg.sender, lpTokenAmount), "withdraw::failed");
      _burn(msg.sender, amount);
    }
  }

  /**
   * @notice Calculate Snowball tokens for a given amount of LP tokens
   * @dev If contract is empty, use 1:1 ratio
   * @dev Could return zero shares for very low amounts of LP tokens
   * @param amount LP tokens
   * @return Snowball tokens
   */
  function getSharesForLPTokens(uint amount) public view returns (uint) {
    if (totalSupply.mul(totalDeposits) == 0) {
      return amount;
    }
    return amount.mul(totalSupply).div(totalDeposits);
  }

  /**
   * @notice Calculate LP tokens for a given amount of Snowball tokens
   * @param amount Snowball tokens
   * @return LP tokens
   */
  function getLPTokensForShares(uint amount) public view returns (uint) {
    if (totalSupply.mul(totalDeposits) == 0) {
      return 0;
    }
    return amount.mul(totalDeposits).div(totalSupply);
  }

  /**
   * @notice Estimate reinvest reward for caller
   * @return Estimated rewards tokens earned for calling `reinvest()`
   */
  function estimateReinvestReward() external view returns (uint) {
    uint unclaimedRewards = stakingContract.earned(address(this));
    if (unclaimedRewards >= MIN_TOKENS_FOR_REINVEST) {
      return unclaimedRewards.mul(REINVEST_FEE_BIPS).div(BIPS_DIVISOR);
    }
    return 0;
  }

  /**
   * @notice Reinvest rewards from staking contract to LP tokens
   */
  function reinvest() external {
    uint unclaimedRewards = stakingContract.earned(address(this));
    require(unclaimedRewards >= MIN_TOKENS_FOR_REINVEST, "MIN_TOKENS_FOR_REINVEST");
    stakingContract.getReward();

    uint adminFee = unclaimedRewards.mul(ADMIN_FEE_BIPS).div(BIPS_DIVISOR);
    if (adminFee > 0) {
      require(rewardToken.transfer(owner(), adminFee), "admin fee transfer failed");
    }

    uint reinvestFee = unclaimedRewards.mul(REINVEST_FEE_BIPS).div(BIPS_DIVISOR);
    if (reinvestFee > 0) {
      require(rewardToken.transfer(owner(), reinvestFee), "reinvest fee transfer failed");
    }

    uint lpTokenAmount = _convertRewardTokensToLpTokens(unclaimedRewards.sub(adminFee).sub(reinvestFee));
    _stakeLpTokens(lpTokenAmount);
  }

  /**
   * @notice Converts entire reward token balance to LP tokens
   * @dev Always converts through router; there are no price checks enabled
   * @return LP tokens received
   */
  function _convertRewardTokensToLpTokens(uint amount) internal returns (uint) {

    uint amountIn = amount.div(2);
    require(amountIn > 0, "rewardToken balance");

    address[] memory path = new address[](2);

    // swap to token0
    path[0] = address(rewardToken);
    path[1] = address(token0);

    uint amountOutToken0 = amountIn;
    if (path[0] != path[1]) {
      uint[] memory amountsOutToken0 = router.getAmountsOut(amountIn, path);
      amountOutToken0 = amountsOutToken0[amountsOutToken0.length - 1];
      router.swapExactTokensForTokens(amountIn, amountOutToken0, path, address(this), block.timestamp);
    }

    // swap to token1
    path[1] = address(token1);

    uint amountOutToken1 = amountIn;
    if (path[0] != path[1]) {
      uint[] memory amountsOutToken1 = router.getAmountsOut(amountIn, path);
      amountOutToken1 = amountsOutToken1[amountsOutToken1.length - 1];
      router.swapExactTokensForTokens(amountIn, amountOutToken1, path, address(this), block.timestamp);
    }

    (,,uint liquidity) = router.addLiquidity(
      address(token0), address(token1),
      amountOutToken0, amountOutToken1,
      0, 0,
      address(this),
      block.timestamp
    );

    return liquidity;
  }

  /**
   * @notice Stakes LP tokens in Staking Contract
   * @dev pass zero to stake entire balance
   * @param amount LP tokens to stake
   */
  function _stakeLpTokens(uint amount) internal {
    if (amount == 0) {
      amount = lpToken.balanceOf(address(this));
    }
    require(amount > 0, "_stakeLpTokens");
    totalDeposits = totalDeposits.add(amount);
    stakingContract.stake(amount);
  }

  /**
   * @notice Withdraws LP tokens from Staking Contract
   * @dev Rewards are not automatically collected from the Staking Contract
   * @param amount LP tokens to remove;
   */
  function _withdrawLpTokens(uint amount) internal {
    require(amount > 0, "_withdrawLpTokens");
    totalDeposits = totalDeposits.sub(amount);
    stakingContract.withdraw(amount);
  }

  /**
   * @notice Allows exit from Staking Contract without additional logic
   * @dev Restricted to onlyOwner
   */
  function emergencyWithdraw() external onlyOwner {
    stakingContract.exit();
  }

  /**
   * @notice Update reinvest minimum threshold
   * @param newValue min threshold in wei
   */
  function updateMinTokensToReinvest(uint256 newValue) external onlyOwner {
    uint oldValue = MIN_TOKENS_FOR_REINVEST;
    MIN_TOKENS_FOR_REINVEST = newValue;
    emit UpdateMinTokensToReinvest(oldValue, newValue);
  }

  /**
   * @notice Update admin fee
   * @dev Total fees cannot be greater than BIPS_DIVISOR (100%)
   * @param newValue specified in BIPS
   */
  function updateAdminFee(uint256 newValue) external onlyOwner {
    require(newValue.add(REINVEST_FEE_BIPS) <= BIPS_DIVISOR, "admin fee too high");
    uint oldFee = ADMIN_FEE_BIPS;
    ADMIN_FEE_BIPS = newValue;
    emit UpdateAdminFee(oldFee, newValue);
  }

  /**
   * @notice Update reinvest fee
   * @dev Total fees cannot be greater than BIPS_DIVISOR (100%)
   * @param newValue specified in BIPS
   */
  function updateReinvestFee(uint256 newValue) external onlyOwner {
    require(newValue.add(ADMIN_FEE_BIPS) <= BIPS_DIVISOR, "reinvest fee too high");
    uint oldFee = REINVEST_FEE_BIPS;
    REINVEST_FEE_BIPS = newValue;
    emit UpdateAdminFee(oldFee, newValue);
  }

  function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
    // require(tokenAddress != address(stakingToken), "Cannot withdraw the staking token");
    IERC20(tokenAddress).transfer(msg.sender, tokenAmount);
    emit Recovered(tokenAddress, tokenAmount);
  }
}