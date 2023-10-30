// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../../interfaces/IYakStrategy.sol";
import "./../../../interfaces/IERC20.sol";
import "./../../../interfaces/IWETH.sol";

import "./interfaces/IMuxDepositor.sol";
import "./interfaces/IMuxRewardRouter.sol";
import "./interfaces/IMuxRewardTracker.sol";
import "./interfaces/IMuxProxy.sol";
import "./interfaces/IVault.sol";
import "./interfaces/ILiquidityPool.sol";
import "./interfaces/IDistributor.sol";

import "./MuxOrderHandler.sol";

library SafeProxy {
    function safeExecute(IMuxDepositor muxDepositor, address target, uint256 value, bytes memory data)
        internal
        returns (bytes memory)
    {
        (bool success, bytes memory returnValue) = muxDepositor.execute(target, value, data);
        if (!success) revert("MuxProxy::safeExecute failed");
        return returnValue;
    }
}

contract MuxProxy is IMuxProxy {
    using SafeProxy for IMuxDepositor;

    uint256 internal constant BIPS_DIVISOR = 10000;

    address internal constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address internal constant MLP = 0x7CbaF5a14D953fF896E5B3312031515c858737C8;
    address internal constant MUX = 0x8BB2Ac0DCF1E86550534cEE5E9C8DED4269b679B;

    address public devAddr;
    address public approvedStrategy;

    MuxOrderHandler public immutable orderHandler;
    IMuxDepositor public immutable override muxDepositor;
    address public immutable override muxRewardRouter;
    address public immutable mlpFeeTracker;
    address public immutable votingEscrow;
    address public immutable orderBook;

    modifier onlyDev() {
        require(msg.sender == devAddr, "MuxProxy::onlyDev");
        _;
    }

    modifier onlyStrategy() {
        require(approvedStrategy == msg.sender, "MuxProxy:onlyStrategy");
        _;
    }

    modifier onlyStrategyAndOrderHandler() {
        require(approvedStrategy == msg.sender || address(orderHandler) == msg.sender, "MuxProxy:onlyStrategy");
        _;
    }

    constructor(address _muxDepositor, address _muxRewardRouter, uint256 _largeOrderThreshold, address _devAddr) {
        require(_devAddr > address(0), "MuxProxy::Invalid dev address provided");
        devAddr = _devAddr;
        muxDepositor = IMuxDepositor(_muxDepositor);
        muxRewardRouter = _muxRewardRouter;
        mlpFeeTracker = IMuxRewardRouter(_muxRewardRouter).mlpFeeTracker();
        votingEscrow = IMuxRewardRouter(_muxRewardRouter).votingEscrow();
        IVault vault = IVault(IMuxRewardRouter(_muxRewardRouter).vault());
        orderBook = vault.orderBook();
        ILiquidityPool.Asset[] memory assets = ILiquidityPool(vault.liquidityPool()).getAllAssetInfo();
        uint8 assetId;
        for (uint256 i; i < assets.length; i++) {
            if (assets[i].tokenAddress == WETH) {
                assetId = assets[i].id;
                break;
            }
        }
        orderHandler =
            new MuxOrderHandler(address(this), _muxDepositor, orderBook, assetId, _largeOrderThreshold, _devAddr);
    }

    function updateDevAddr(address _newValue) public onlyDev {
        require(_newValue > address(0), "MuxProxy::Invalid address provided");
        devAddr = _newValue;
    }

    function approveStrategy(address _strategy) external onlyDev {
        require(approvedStrategy == address(0), "MuxProxy::Strategy already defined");
        approvedStrategy = _strategy;
    }

    function largePendingOrder() external view returns (bool) {
        return orderHandler.largePendingOrder();
    }

    function stakeMlp(uint256 _amount) external override onlyStrategyAndOrderHandler {
        muxDepositor.safeExecute(MLP, 0, abi.encodeWithSignature("approve(address,uint256)", mlpFeeTracker, _amount));
        muxDepositor.safeExecute(muxRewardRouter, 0, abi.encodeWithSignature("stakeMlp(uint256)", _amount));
    }

    function withdrawMlp(uint256 _amount) external override onlyStrategy {
        muxDepositor.safeExecute(muxRewardRouter, 0, abi.encodeWithSignature("unstakeMlp(uint256)", _amount));
        muxDepositor.safeExecute(MLP, 0, abi.encodeWithSignature("transfer(address,uint256)", msg.sender, _amount));
    }

    function orderMlp(uint256 _amount) external override onlyStrategy {
        IERC20(WETH).transfer(address(orderHandler), _amount);
        orderHandler.orderMlp(_amount);
    }

    function pendingRewards() external view override returns (uint256) {
        IMuxRewardTracker rewardTracker = IMuxRewardTracker(mlpFeeTracker);

        uint256 rewardUnaccounted = IERC20(WETH).balanceOf(mlpFeeTracker);
        rewardUnaccounted += IDistributor(rewardTracker.distributor()).pendingMlpRewards();
        rewardUnaccounted -= rewardTracker.lastRewardBalance();

        uint256 tSupply = rewardTracker.totalSupply();
        uint256 cumulativeRewardPerToken = rewardTracker.cumulativeRewardPerToken();

        if (tSupply > 0 && rewardUnaccounted > 0) {
            cumulativeRewardPerToken += ((rewardUnaccounted * 1e18) / tSupply);
        }
        uint256 accountReward = (
            rewardTracker.stakedAmounts(address(muxDepositor))
                * (cumulativeRewardPerToken - rewardTracker.previousCumulatedRewardPerToken(address(muxDepositor)))
        ) / 1e18;

        return IMuxRewardTracker(mlpFeeTracker).claimableReward(address(muxDepositor)) + accountReward;
    }

    function claimReward() external override onlyStrategy {
        muxDepositor.safeExecute(muxRewardRouter, 0, abi.encodeWithSignature("claimFromMlp()"));
        muxDepositor.safeExecute(muxRewardRouter, 0, abi.encodeWithSignature("claimFromVe()"));
        uint256 reward = IERC20(WETH).balanceOf(address(muxDepositor));
        muxDepositor.safeExecute(WETH, 0, abi.encodeWithSignature("transfer(address,uint256)", msg.sender, reward));
        uint256 muxBalance = IERC20(MUX).balanceOf(address(muxDepositor));
        if (muxBalance > 0) {
            muxDepositor.safeExecute(
                MUX, 0, abi.encodeWithSignature("approve(address,uint256)", votingEscrow, muxBalance)
            );
            uint256 unlockTime = ((block.timestamp + (4 * 365 * 1 days)) / 1 weeks) * 1 weeks;
            muxDepositor.safeExecute(
                votingEscrow,
                0,
                abi.encodeWithSignature("deposit(address,uint256,uint256)", MUX, muxBalance, unlockTime)
            );
        }
    }

    function totalDeposits() external view override returns (uint256) {
        return IMuxRewardRouter(muxRewardRouter).stakedMlpAmount(address(muxDepositor));
    }
}
