// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../../interfaces/IYakStrategy.sol";
import "../../../lib/SafeERC20.sol";
import "../../../lib/SafeMath.sol";

import "./interfaces/IGmxDepositor.sol";
import "./interfaces/IGmxRewardRouter.sol";
import "./interfaces/IGmxRewardTracker.sol";
import "./interfaces/IGmxProxy.sol";

library SafeProxy {
    function safeExecute(
        IGmxDepositor gmxDepositor,
        address target,
        uint256 value,
        bytes memory data
    ) internal returns (bytes memory) {
        (bool success, bytes memory returnValue) = gmxDepositor.execute(target, value, data);
        if (!success) revert("GmxProxy::safeExecute failed");
        return returnValue;
    }
}

contract GmxProxy is IGmxProxy {
    using SafeMath for uint256;
    using SafeProxy for IGmxDepositor;
    using SafeERC20 for IERC20;

    uint256 internal constant BIPS_DIVISOR = 10000;

    address internal constant GMX = 0x62edc0692BD897D2295872a9FFCac5425011c661;
    address internal constant fsGLP = 0x5643F4b25E36478eE1E90418d5343cb6591BcB9d;
    address internal constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;

    address public devAddr;
    mapping(address => address) public approvedStrategies;

    IGmxDepositor public immutable override gmxDepositor;
    address public immutable override gmxRewardRouter;

    address internal immutable gmxRewardTracker;
    address internal immutable glpManager;

    modifier onlyDev() {
        require(msg.sender == devAddr, "GmxProxy::onlyDev");
        _;
    }

    modifier onlyStrategy() {
        require(
            approvedStrategies[fsGLP] == msg.sender || approvedStrategies[GMX] == msg.sender,
            "GmxProxy:onlyGLPStrategy"
        );
        _;
    }

    modifier onlyGLPStrategy() {
        require(approvedStrategies[fsGLP] == msg.sender, "GmxProxy:onlyGLPStrategy");
        _;
    }

    modifier onlyGMXStrategy() {
        require(approvedStrategies[GMX] == msg.sender, "GmxProxy::onlyGMXStrategy");
        _;
    }

    constructor(
        address _gmxDepositor,
        address _gmxRewardRouter,
        address _devAddr
    ) {
        devAddr = _devAddr;
        gmxDepositor = IGmxDepositor(_gmxDepositor);
        gmxRewardRouter = _gmxRewardRouter;
        gmxRewardTracker = IGmxRewardRouter(_gmxRewardRouter).stakedGmxTracker();
        glpManager = IGmxRewardRouter(_gmxRewardRouter).glpManager();
    }

    function updateDevAddr(address newValue) public onlyDev {
        devAddr = newValue;
    }

    function approveStrategy(address _strategy) external onlyDev {
        address depositToken = IYakStrategy(_strategy).depositToken();
        require(approvedStrategies[depositToken] == address(0), "GmxProxy::Strategy for deposit token already added");
        approvedStrategies[depositToken] = _strategy;
    }

    function buyAndStakeGlp(uint256 _amount) external override onlyGLPStrategy returns (uint256) {
        IERC20(WAVAX).safeTransfer(address(gmxDepositor), _amount);
        gmxDepositor.safeExecute(WAVAX, 0, abi.encodeWithSignature("approve(address,uint256)", glpManager, _amount));
        bytes memory result = gmxDepositor.safeExecute(
            gmxRewardRouter,
            0,
            abi.encodeWithSignature("mintAndStakeGlp(address,uint256,uint256,uint256)", WAVAX, _amount, 0, 0)
        );
        gmxDepositor.safeExecute(WAVAX, 0, abi.encodeWithSignature("approve(address,uint256)", glpManager, 0));
        return toUint256(result, 0);
    }

    function withdrawGlp(uint256 _amount) external override onlyGLPStrategy {
        _withdrawGlp(_amount);
    }

    function _withdrawGlp(uint256 _amount) private {
        gmxDepositor.safeExecute(fsGLP, 0, abi.encodeWithSignature("transfer(address,uint256)", msg.sender, _amount));
    }

    function stakeGmx(uint256 _amount) external override onlyGMXStrategy {
        IERC20(GMX).safeTransfer(address(gmxDepositor), _amount);
        gmxDepositor.safeExecute(
            GMX,
            0,
            abi.encodeWithSignature("approve(address,uint256)", gmxRewardTracker, _amount)
        );
        gmxDepositor.safeExecute(gmxRewardRouter, 0, abi.encodeWithSignature("stakeGmx(uint256)", _amount));
        gmxDepositor.safeExecute(GMX, 0, abi.encodeWithSignature("approve(address,uint256)", gmxRewardTracker, 0));
    }

    function withdrawGmx(uint256 _amount) external override onlyGMXStrategy {
        _withdrawGmx(_amount);
    }

    function _withdrawGmx(uint256 _amount) private {
        gmxDepositor.safeExecute(gmxRewardRouter, 0, abi.encodeWithSignature("unstakeGmx(uint256)", _amount));
        gmxDepositor.safeExecute(GMX, 0, abi.encodeWithSignature("transfer(address,uint256)", msg.sender, _amount));
    }

    function _compoundEsGmx() private {
        gmxDepositor.safeExecute(address(gmxRewardRouter), 0, abi.encodeWithSignature("compound()"));
    }

    function pendingRewards(address _rewardTracker) external view override returns (uint256) {
        return IGmxRewardTracker(_rewardTracker).claimable(address(gmxDepositor));
    }

    function claimReward(address rewardTracker) external override onlyStrategy {
        gmxDepositor.safeExecute(rewardTracker, 0, abi.encodeWithSignature("claim(address)", msg.sender));
        _compoundEsGmx();
    }

    function totalDeposits(address _rewardTracker) external view override returns (uint256) {
        address depositToken = IYakStrategy(msg.sender).depositToken();
        if (depositToken == GMX) {
            address rewardTracker = IGmxRewardRouter(gmxRewardRouter).stakedGmxTracker();
            return IGmxRewardTracker(rewardTracker).depositBalances(address(gmxDepositor), depositToken);
        }
        return IGmxRewardTracker(_rewardTracker).stakedAmounts(address(gmxDepositor));
    }

    function emergencyWithdrawGLP(uint256 _balance) external override onlyGLPStrategy {
        _withdrawGlp(_balance);
    }

    function emergencyWithdrawGMX(uint256 _balance) external override onlyGMXStrategy {
        _withdrawGmx(_balance);
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
