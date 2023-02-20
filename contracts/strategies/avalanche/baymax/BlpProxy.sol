// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../../lib/SafeERC20.sol";

import "./interfaces/IBayDepositor.sol";
import "./interfaces/IBlpProxy.sol";
import "./interfaces/IGmxRewardRouter.sol";
import "./interfaces/IGmxRewardTracker.sol";

library SafeProxy {
    function safeExecute(
        IBayDepositor gmxDepositor,
        address target,
        uint256 value,
        bytes memory data
    ) internal returns (bytes memory) {
        (bool success, bytes memory returnValue) = gmxDepositor.execute(target, value, data);
        if (!success) revert("BlpProxy::safeExecute failed");
        return returnValue;
    }
}

contract BlpProxy is IBlpProxy {
    using SafeProxy for IBayDepositor;
    using SafeERC20 for IERC20;

    uint256 internal constant BIPS_DIVISOR = 10000;

    address internal constant sGLP = 0x9a4E5E7fbb3Bbf0F04b78354aaFEA877E346ae33;
    address internal constant esGMX = 0x8d5618aa319d99A8A8396e8a855115dfEa5E84a4;
    address internal constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;

    address public devAddr;
    address public approvedStrategy;

    IBayDepositor public immutable override gmxDepositor;
    address public immutable override gmxRewardRouter;

    address internal immutable stakedGlpTracker;
    address internal immutable glpManager;

    modifier onlyDev() {
        require(msg.sender == devAddr, "BlpProxy::onlyDev");
        _;
    }

    modifier onlyStrategy() {
        require(approvedStrategy == msg.sender, "BlpProxy::onlyStrategy");
        _;
    }

    constructor(
        address _gmxDepositor,
        address _gmxRewardRouter,
        address _devAddr
    ) {
        require(_gmxDepositor > address(0), "BlpProxy::Invalid depositor address provided");
        require(_gmxRewardRouter > address(0), "BlpProxy::Invalid reward router address provided");
        require(_devAddr > address(0), "BlpProxy::Invalid dev address provided");
        devAddr = _devAddr;
        gmxDepositor = IBayDepositor(_gmxDepositor);
        gmxRewardRouter = _gmxRewardRouter;
        stakedGlpTracker = IGmxRewardRouter(_gmxRewardRouter).stakedGlpTracker();
        glpManager = IGmxRewardRouter(_gmxRewardRouter).glpManager();
    }

    function updateDevAddr(address newValue) public onlyDev {
        require(newValue > address(0), "BlpProxy::Invalid dev address provided");
        devAddr = newValue;
    }

    function approveStrategy(address _strategy) external onlyDev {
        require(approvedStrategy == address(0), "BlpProxy::Strategy for deposit token already added");
        approvedStrategy = _strategy;
    }

    function stakeESGMX() external onlyDev {
        gmxDepositor.safeExecute(
            gmxRewardRouter,
            0,
            abi.encodeWithSignature("stakeEsGmx(uint256)", IERC20(esGMX).balanceOf(address(gmxDepositor)))
        );
    }

    function buyAndStakeGlp(uint256 _amount) external override onlyStrategy returns (uint256) {
        gmxDepositor.safeExecute(WAVAX, 0, abi.encodeWithSignature("approve(address,uint256)", glpManager, _amount));
        bytes memory result = gmxDepositor.safeExecute(
            gmxRewardRouter,
            0,
            abi.encodeWithSignature("mintAndStakeGlp(address,uint256,uint256,uint256)", WAVAX, _amount, 0, 0)
        );
        gmxDepositor.safeExecute(WAVAX, 0, abi.encodeWithSignature("approve(address,uint256)", glpManager, 0));
        return toUint256(result, 0);
    }

    function withdrawGlp(uint256 _amount) external override onlyStrategy {
        _withdrawGlp(_amount);
    }

    function _withdrawGlp(uint256 _amount) private {
        gmxDepositor.safeExecute(sGLP, 0, abi.encodeWithSignature("transfer(address,uint256)", msg.sender, _amount));
    }

    function pendingRewards() external view override returns (uint256) {
        return IGmxRewardTracker(IGmxRewardRouter(gmxRewardRouter).feeGlpTracker()).claimable(address(gmxDepositor));
    }

    function claimReward() external override onlyStrategy {
        gmxDepositor.safeExecute(
            gmxRewardRouter,
            0,
            abi.encodeWithSignature(
                "handleRewards(bool,bool,bool,bool,bool,bool,bool)",
                false, // bool _shouldClaimGmx
                false, // bool _shouldStakeGmx
                true, // bool _shouldClaimEsGmx
                true, // bool _shouldStakeEsGmx
                true, // bool _shouldStakeMultiplierPoints
                true, // bool _shouldClaimWeth
                false // bool _shouldConvertWethToEth
            )
        );
        uint256 reward = IERC20(WAVAX).balanceOf(address(gmxDepositor));
        gmxDepositor.safeExecute(WAVAX, 0, abi.encodeWithSignature("transfer(address,uint256)", msg.sender, reward));
    }

    function totalDeposits() external view override returns (uint256) {
        return IGmxRewardTracker(stakedGlpTracker).stakedAmounts(address(gmxDepositor));
    }

    function emergencyWithdraw(uint256 _balance) external override onlyStrategy {
        _withdrawGlp(_balance);
    }

    function toUint256(bytes memory _bytes, uint256 _start) internal pure returns (uint256) {
        require(_bytes.length >= _start + 32, "toUint256_outOfBounds");
        uint256 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x20), _start))
        }

        return tempUint;
    }
}
