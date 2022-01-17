// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity 0.7.3;

import "../interfaces/IMasterPlatypus.sol";
import "../interfaces/IPlatypusPool.sol";
import "../interfaces/IPlatypusVoterProxy.sol";
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
    IPlatypusVoterProxy public proxy;
    uint256 public maxSlippage;
    IERC20 public immutable asset;
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
        asset = IERC20(pool.assetOf(_depositToken));
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

    function _depositMasterchef(uint256 _pid, uint256 _amount) internal override {
        depositToken.safeTransfer(address(proxy), _amount);
        proxy.deposit(_pid, address(masterchef), address(pool), address(depositToken), address(asset), _amount);
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
                _amount
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
        (uint256 pendingPtp, address bonusTokenAddress, , uint256 pendingBonusToken) = masterchef.pendingTokens(
            _pid,
            proxy.platypusVoter()
        );
        uint256 ptpFee = proxy.ptpFee();
        uint256 boostFee = pendingPtp.mul(ptpFee).div(BIPS_DIVISOR);

        return (pendingPtp.sub(boostFee), pendingBonusToken, bonusTokenAddress);
    }

    function _getRewards(uint256 _pid) internal override {
        proxy.claimReward(address(masterchef), _pid, address(asset));
    }

    function _getDepositBalance(uint256 _pid) internal view override returns (uint256 amount) {
        (uint256 balance, , ) = masterchef.userInfo(_pid, proxy.platypusVoter());
        return balance;
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
