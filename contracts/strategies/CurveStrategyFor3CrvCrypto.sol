// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "../YakStrategyV2.sol";
import "../interfaces/IDepositZap.sol";
import "../interfaces/IPair.sol";
import "../lib/DexLibrary.sol";
import "../interfaces/ILiquidityGuage.sol";

/**
 * @notice 3CrvCrypto strategy for Cruve pools
 */
contract CurveStrategyFor3CrvCrypto is YakStrategyV2 {
  using SafeMath for uint;

  ILiquidityGuage public stakingContract;
  IDepositZap public depositZap;
  IPair private swapPairWAVAXCRV;
  IPair private swapPairToken0;
  IPair private swapPairToken1;
  uint private numberOfPoolTokens;

  address private constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
  struct PoolTokenForSwap {
    address swapPairToken;
    uint decimalAdjustment;
    uint indexOfPoolToken;
  }
  PoolTokenForSwap private swapPair0;
  PoolTokenForSwap private swapPair1;
  uint private decimalAdjustment0;
  uint private decimalAdjustment1;

  constructor(
    string memory _name,
    address _depositToken, 
    address _rewardToken, 
    address _stakingContract,
    address _depositZap,
    address _swapPairWAVAXCRV,
    PoolTokenForSwap memory _swapToken0,
    PoolTokenForSwap memory _swapToken1,
    uint _numberOfPoolTokens,
    address _timelock,
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
    stakingContract = ILiquidityGuage(_stakingContract);
    depositZap = IDepositZap(_depositZap);
    decimalAdjustment0 = _decimalAdjustment0;
    decimalAdjustment1 = _decimalAdjustment1;
    devAddr = msg.sender;
    numberOfPoolTokens = _numberOfPoolTokens;
    swapPair0 = _swapToken0;
    swapPair1 = _swapToken1;
    assignSwapPairSafely(
            swapPairWAVAXCRV,
            _swapToken0.swapPairToken,
            swapPairToken.swapPairToken,
            _rewardToken
        );
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
    IERC20(swapPairToken0.token0).approve(address(depositZap), MAX_UINT);
    IERC20(swapPairToken1.token1).approve(address(depositZap), MAX_UINT);
  }

  /**
     * @notice Initialization helper for Pair deposit tokens
     * @dev Checks that selected Pairs are valid for trading reward tokens
     * @dev Assigns values to swapPairToken0 and swapPairToken1
     */
    function assignSwapPairSafely(
        address _swapPairWAVAXCRV,
        address _swapPairToken0,
        address _swapPairToken1,
        address _rewardToken
    ) private {
        require(
            DexLibrary.checkSwapPairCompatibility(
                IPair(_swapPairWAVAXCRV),
                address(WAVAX),
                address(_rewardToken)
            ),
            "_swapPairWAVAXCRV is not a WAVAX-CRV pair"
        );
        require(
            _swapPairToken0 == address(0) ||
                DexLibrary.checkSwapPairCompatibility(
                    IPair(_swapPairToken0),
                    address(WAVAX),
                    IPair(address(depositToken)).token0()
                ),
            "_swapPairToken0 is not a WAVAX+deposit token0"
        );
        require(
            _swapPairToken1 == address(0) ||
                DexLibrary.checkSwapPairCompatibility(
                    IPair(_swapPairToken1),
                    address(WAVAX),
                    IPair(address(depositToken)).token1()
                ),
            "_swapPairToken0 is not a WAVAX+deposit token1"
        );
        // converts CRV to WAVAX
        swapPairWAVAXCRV = IPair(_swapPairWAVAXCRV);
        // converts WAVAX to pair token0
        swapPairToken0 = IPair(_swapPairToken0);
        // converts WAVAX to pair token1
        swapPairToken1 = IPair(_swapPairToken1);
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
    require(DEPOSITS_ENABLED == true, "CurveStrategyFor3CrvCrypto::_deposit");
    if (MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST > 0) {
        uint unclaimedRewards = checkReward();
        if (unclaimedRewards > MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST) {
            _reinvest(unclaimedRewards);
        }
    }
    require(depositToken.transferFrom(msg.sender, address(this), amount));
    _mint(account, getSharesForDepositTokens(amount));
    _stakeDepositTokens(amount);
    emit Deposit(account, amount);
  }

  function withdraw(uint amount) external override {
    uint depositTokenAmount = getDepositTokensForShares(amount);
    if (depositTokenAmount > 0) {
      _withdrawDepositTokens(depositTokenAmount);
       _safeTransfer(
                address(depositToken),
                msg.sender,
                depositTokenAmount
            );
      _burn(msg.sender, amount);
      emit Withdraw(msg.sender, depositTokenAmount);
    }
  }

  function _withdrawDepositTokens(uint amount) private {
    require(amount > 0, "CurveStrategyFor3CrvCrypto::_withdrawDepositTokens");
    stakingContract.withdraw(amount);
  }

  function reinvest() external override onlyEOA {
    uint unclaimedRewards = checkReward();
    require(unclaimedRewards >= MIN_TOKENS_TO_REINVEST, "CurveStrategyFor3CrvCrypto::reinvest");
    _reinvest(unclaimedRewards);
  }

  /**
    * @notice Reinvest rewards from staking contract to deposit tokens
    * @dev Reverts if the expected amount of tokens are not returned from `stakingContract`
    * @param amount deposit tokens to reinvest
    */
  function _reinvest(uint amount) private {
    stakingContract.claim_rewards();
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
    require(amount > 0, "CurveStrategyFor3CrvCrypto::_stakeDepositTokens");
    stakingContract.deposit( amount, address(this));
  }

  function totalDeposits() public override view returns (uint) {
        return stakingContract.balanceOf( address(this));
    }

  function checkReward() public override view returns (uint) {
    uint pendingReward = stakingContract.claim_rewards();
    uint contractBalance = rewardToken.balanceOf(address(this));
    return pendingReward.add(contractBalance);
  }

  /**
    * @notice Converts reward tokens to deposit tokens
    * @dev No price checks enabled
    * @return deposit tokens received
    */
  function _convertRewardTokensToDepositTokens(uint amount) private returns (uint) {
    require(amount > 0, "CurveStrategyFor3CrvCrypto::_convertRewardTokensToDepositTokens");

    // uint convertedAmountWAVAX = DexLibrary.swap(
    //   amount,
    //   address(rewardToken), address(WAVAX),
    //   swapPairWAVAXCRV
    // );
    uint liquidity = 0;

    // find route for bonus token
    uint[] memory liquidityAmounts0 = new uint[](numberOfPoolTokens);
    // what if we convert to 0
      liquidityAmounts0[swapPair0.indexOfPoolToken] = DexLibrary.estimateConversionThroughPair(
        amount,
        address(WAVAX), depositZap.underlying_coins(swapPair0.indexOfPoolToken),
        swapPairToken0
      );
      uint lpToken0 = depositZap.calc_token_amount(liquidityAmounts0,false);
      uint[] memory liquidityAmounts1 = new uint[](numberOfPoolTokens);
    //what if we convert to 1
      liquidityAmounts1[swapPair1.indexOfPoolToken] = DexLibrary.estimateConversionThroughPair(
        amount,
        address(WAVAX), depositZap.underlying_coins(swapPair1.indexOfPoolToken),
        swapPairToken1
      );
      uint lpToken1 = depositZap.calc_token_amount(liquidityAmounts1,false);
      if(lptoken0>lptoken1){
        liquidityAmounts0[swapPair0.indexOfPoolToken] = DexLibrary.swap(
        amount,
        address(WAVAX), depositZap.underlying_coins(swapPair0.indexOfPoolToken),
        swapPairToken0
        );
      depositZap.add_liquidity(liquidityAmounts0,lptoken1);
      } else {
        liquidityAmounts1[swapPair1.indexOfPoolToken] = DexLibrary.swap(
        amount,
        address(WAVAX), depositZap.underlying_coins(swapPair1.indexOfPoolToken),
        swapPairToken1
        );
      depositZap.add_liquidity(liquidityAmounts1,lptoken0);
      }

    return liquidity;
  }

  /**
   * @notice Estimate recoverable balance
   * @return deposit tokens
   */
  function estimateDeployedBalance() external override view returns (uint) {
    uint depositBalance = stakingContract.balanceOf(address(this));
    return depositBalance;
  }

  function rescueDeployedFunds(uint minReturnAmountAccepted, bool disableDeposits) external override onlyOwner {
    uint balanceBefore = depositToken.balanceOf(address(this));
    stakingContract.withdraw(stakingContract.balanceOf(address(this)));
    uint balanceAfter = depositToken.balanceOf(address(this));
    require(balanceAfter.sub(balanceBefore) >= minReturnAmountAccepted, "GondolaStrategyForPoolV2::rescueDeployedFunds");
    totalDeposits = balanceAfter;
    emit Reinvest(totalDeposits, totalSupply);
    if (DEPOSITS_ENABLED == true && disableDeposits == true) {
      updateDepositsEnabled(false);
    }
  }
}