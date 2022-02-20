// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity 0.7.3;

import "../interfaces/IMasterPlatypus.sol";
import "../interfaces/IPlatypusPool.sol";
import "../interfaces/IPlatypusVoterProxy.sol";
import "../interfaces/IPlatypusAsset.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IPair.sol";
import "../interfaces/IWAVAX.sol";
import "../lib/DexLibrary.sol";
import "../lib/SafeERC20.sol";
import "../lib/DSMath.sol";
import "./PlatypusMasterChefStrategy.sol";

contract PlatypusStrategy is PlatypusMasterChefStrategy {
    using SafeMath for uint256;
    using DSMath for uint256;
    using SafeERC20 for IERC20;

    IWAVAX private constant WAVAX = IWAVAX(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);
    uint256 internal constant WAD = 10**18;
    uint256 internal constant RAY = 10**27;

    IMasterPlatypus public immutable masterchef;
    IPlatypusAsset public immutable asset;
    IPlatypusPool public pool;
    IPlatypusVoterProxy public proxy;
    uint256 public maxSlippage;
    address private swapPairToken;

    struct SwapPairs {
        address swapPairToken; // swap rewardToken to depositToken
        address swapPairPoolReward;
        address swapPairExtraReward;
    }

    constructor(
        string memory _name,
        address _depositToken,
        address _poolRewardToken,
        SwapPairs memory swapPairs,
        address _pool,
        address _stakingContract,
        address _voterProxy,
        uint256 _pid,
        address _timelock,
        StrategySettings memory _strategySettings
    )
        PlatypusMasterChefStrategy(
            _name,
            _depositToken,
            address(WAVAX), /*rewardToken=*/
            _poolRewardToken,
            swapPairs.swapPairPoolReward,
            swapPairs.swapPairExtraReward,
            _stakingContract,
            _timelock,
            _pid,
            _strategySettings
        )
    {
        masterchef = IMasterPlatypus(_stakingContract);
        pool = IPlatypusPool(_pool);
        asset = IPlatypusAsset(pool.assetOf(_depositToken));
        proxy = IPlatypusVoterProxy(_voterProxy);
        maxSlippage = 50;
        assignSwapPairSafely(swapPairs.swapPairToken);
    }

    function setPlatypusVoterProxy(address _voterProxy) external onlyOwner {
        proxy = IPlatypusVoterProxy(_voterProxy);
    }

    function updateMaxWithdrawSlippage(uint256 slippageBips) public onlyDev {
        maxSlippage = slippageBips;
    }

    function assignSwapPairSafely(address _swapPairToken) private {
        require(
            DexLibrary.checkSwapPairCompatibility(IPair(_swapPairToken), address(depositToken), address(rewardToken)),
            "swap token does not match deposit and reward token"
        );
        swapPairToken = _swapPairToken;
    }

    function _convertRewardTokenToDepositToken(uint256 fromAmount) internal override returns (uint256 toAmount) {
        toAmount = DexLibrary.swap(fromAmount, address(rewardToken), address(depositToken), IPair(swapPairToken));
    }

    function _depositMasterchef(
        uint256 _pid,
        uint256 _amount,
        uint256 _depositFee
    ) internal override {
        depositToken.safeTransfer(address(proxy), _amount);
        proxy.deposit(
            _pid,
            address(masterchef),
            address(pool),
            address(depositToken),
            address(asset),
            _amount,
            _depositFee
        );
    }

    function _calculateDepositFee(uint256 amount) internal view override returns (uint256 fee) {
        return
            _depositFee(
                pool.getSlippageParamK(),
                pool.getSlippageParamN(),
                pool.getC1(),
                pool.getXThreshold(),
                asset.cash(),
                asset.liability(),
                amount
            );
    }

    function _depositFee(
        uint256 k,
        uint256 n,
        uint256 c1,
        uint256 xThreshold,
        uint256 cash,
        uint256 liability,
        uint256 amount
    ) internal pure returns (uint256) {
        // cover case where the asset has no liquidity yet
        if (liability == 0) {
            return 0;
        }

        uint256 covBefore = cash.wdiv(liability);
        if (covBefore <= 10**18) {
            return 0;
        }

        uint256 covAfter = (cash.add(amount)).wdiv(liability.add(amount));
        uint256 slippageBefore = _slippageFunc(k, n, c1, xThreshold, covBefore);
        uint256 slippageAfter = _slippageFunc(k, n, c1, xThreshold, covAfter);

        // (Li + Di) * g(cov_after) - Li * g(cov_before)
        return ((liability.add(amount)).wmul(slippageAfter)) - (liability.wmul(slippageBefore));
    }

    function _slippageFunc(
        uint256 k,
        uint256 n,
        uint256 c1,
        uint256 xThreshold,
        uint256 x
    ) internal pure returns (uint256) {
        if (x < xThreshold) {
            return c1.sub(x);
        } else {
            return k.wdiv((((x.mul(RAY)).div(WAD)).rpow(n).mul(WAD)).div(RAY)); // k / (x ** n)
        }
    }

    function _withdrawMasterchef(uint256 _pid, uint256 _amount) internal override returns (uint256 withdrawalAmount) {
        return
            proxy.withdraw(
                _pid,
                address(masterchef),
                address(pool),
                address(depositToken),
                address(asset),
                maxSlippage,
                _amount,
                totalDeposits()
            );
    }

    function _pendingRewards(uint256 _pid)
        internal
        view
        override
        returns (
            uint256,
            uint256,
            address
        )
    {
        (uint256 pendingPtp, uint256 pendingBonusToken, address bonusTokenAddress) = proxy.pendingRewards(
            address(masterchef),
            _pid
        );
        uint256 reinvestFeeBips = proxy.reinvestFeeBips();
        uint256 boostFee = pendingPtp.mul(reinvestFeeBips).div(BIPS_DIVISOR);

        return (pendingPtp.sub(boostFee), pendingBonusToken, bonusTokenAddress);
    }

    function _getRewards(uint256 _pid) internal override {
        proxy.claimReward(address(masterchef), _pid);
    }

    function _getDepositBalance(uint256 _pid) internal view override returns (uint256 amount) {
        return proxy.poolBalance(address(masterchef), _pid);
    }

    /**
     * @notice Estimate recoverable balance after withdraw fee
     * @return deposit tokens after withdraw fee
     */
    function estimateDeployedBalance() external view override returns (uint256) {
        uint256 balance = totalDeposits();
        if (balance == 0) {
            return 0;
        }
        (uint256 expectedAmount, , ) = pool.quotePotentialWithdraw(address(depositToken), balance);
        return expectedAmount;
    }

    function _emergencyWithdraw(uint256 _pid) internal override {
        proxy.emergencyWithdraw(_pid, address(masterchef), address(pool), address(depositToken), address(asset));
    }
}
