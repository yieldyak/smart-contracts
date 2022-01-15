// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity 0.7.3;

import "../interfaces/IMasterPlatypus.sol";
import "../interfaces/IPlatypusPool.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IPair.sol";
import "../interfaces/IWAVAX.sol";
import "../lib/DexLibrary.sol";
import "../lib/SafeERC20.sol";
import "./PlatypusMasterChefStrategy.sol";
import "hardhat/console.sol";

// For OrcaStaking where reward is in AVAX. Has no deposit fee.
contract PlatypusStrategy is PlatypusMasterChefStrategy {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IWAVAX private constant WAVAX = IWAVAX(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);

    IMasterPlatypus public masterchef;
    IPlatypusPool public pool;
    uint256 public maxSlippage;
    IERC20 public immutable asset;
    address private swapPairToken;

    constructor(
        string memory _name,
        address _depositToken,
        address _swapPairToken, // swap rewardToken to depositToken
        address _poolRewardToken,
        address _swapPairPoolReward,
        address _swapPairExtraReward,
        address _pool,
        address _stakingContract,
        //address _voterProxy,
        uint256 _pid,
        address _timelock,
        StrategySettings memory _strategySettings
    )
        PlatypusMasterChefStrategy(
            _name,
            _depositToken,
            address(WAVAX), /*rewardToken=*/
            _poolRewardToken,
            _swapPairPoolReward,
            _swapPairExtraReward,
            _stakingContract,
            _timelock,
            _pid,
            _strategySettings
        )
    {
        masterchef = IMasterPlatypus(_stakingContract);
        pool = IPlatypusPool(_pool);
        asset = IERC20(pool.assetOf(_depositToken));
        maxSlippage = 50;
        assignSwapPairSafely(_swapPairToken);
    }

    receive() external payable {}

    function updateMaxWithdrawSlippage(uint256 slippageBips) public onlyDev {
        maxSlippage = slippageBips;
    }

    /**
     * @notice Initialization helper for Pair deposit tokens
     * @dev Checks that selected Pairs are valid for trading reward tokens
     * @dev Assigns values to swapPairToken
     */
    function assignSwapPairSafely(address _swapPairToken) private {
        require(
            DexLibrary.checkSwapPairCompatibility(IPair(_swapPairToken), address(depositToken), address(rewardToken)),
            "swap token does not match deposit and reward token"
        );
        swapPairToken = _swapPairToken;
    }

    /* VIRTUAL */
    function _convertRewardTokenToDepositToken(uint256 fromAmount) internal override returns (uint256 toAmount) {
        toAmount = DexLibrary.swap(fromAmount, address(rewardToken), address(depositToken), IPair(swapPairToken));
    }

    function _depositMasterchef(uint256 _pid, uint256 _amount) internal override {
        depositToken.safeApprove(address(pool), _amount);
        uint256 liquidity = pool.deposit(address(depositToken), _amount, address(this), type(uint256).max);
        asset.safeApprove(address(masterchef), liquidity);
        masterchef.deposit(_pid, liquidity);
    }

    function getLiquidityForDepositTokens(uint256 amount) public view returns (uint256) {
        return amount.mul(asset.balanceOf(address(this))).div(totalDeposits());
    }

    function _calculateWithdrawFee(
        uint256, /*pid*/
        uint256 _amount
    ) internal view returns (uint256 fee) {
        (, fee, ) = pool.quotePotentialWithdraw(address(depositToken), _amount);
    }

    function _withdrawMasterchef(uint256 _pid, uint256 _amount) internal override returns (uint256 withdrawalAmount) {
        masterchef.withdraw(_pid, _amount);
        asset.safeApprove(address(pool), _amount);
        uint256 withdrawAmount = _amount.sub(_calculateWithdrawFee(_pid, _amount));
        uint256 slippage = withdrawAmount.mul(maxSlippage).div(BIPS_DIVISOR);
        withdrawAmount = withdrawAmount.sub(slippage);
        uint256 amount = pool.withdraw(
            address(depositToken),
            _amount,
            withdrawAmount,
            address(this),
            type(uint256).max
        );
        return amount;
    }

    /**
     * @notice Estimate recoverable balance after withdraw fee
     * @return deposit tokens after withdraw fee
     */
    function estimateDeployedBalance() external view override returns (uint256) {
        uint256 balance = totalDeposits();
        (uint256 expectedAmount, , ) = pool.quotePotentialWithdraw(address(depositToken), balance);
        return expectedAmount;
    }

    function _emergencyWithdraw(uint256 _pid) internal override {
        masterchef.emergencyWithdraw(_pid);
        uint256 balance = asset.balanceOf(address(this));
        (uint256 expectedAmount, , ) = pool.quotePotentialWithdraw(address(depositToken), balance);
        asset.safeApprove(address(pool), balance);
        pool.withdraw(address(depositToken), balance, expectedAmount, address(this), type(uint256).max);
        asset.safeApprove(address(masterchef), 0);
        depositToken.safeApprove(address(pool), 0);
    }

    function _pendingRewards(uint256 _pid, address _user)
        internal
        view
        override
        returns (
            uint256,
            uint256,
            address
        )
    {
        (uint256 pendingPtp, address bonusTokenAddress, , uint256 pendingBonusToken) = masterchef.pendingTokens(
            _pid,
            _user
        );
        return (pendingPtp, pendingBonusToken, bonusTokenAddress);
    }

    function _getRewards(uint256 _pid) internal override {
        uint256[] memory pids = new uint256[](1);
        pids[0] = _pid;

        masterchef.multiClaim(pids);

        uint256 balance = address(this).balance;
        if (balance > 0) {
            WAVAX.deposit{value: balance}();
        }
    }

    function _getDepositBalance(uint256 _pid, address user) internal view override returns (uint256 amount) {
        (uint256 balance, , ) = masterchef.userInfo(_pid, user);
        return balance;
    }
}
