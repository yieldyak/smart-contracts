// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;
pragma experimental ABIEncoderV2;

import "../interfaces/IGmxDepositor.sol";
import "../interfaces/IGmxRewardRouter.sol";
import "../interfaces/IGmxRewardTracker.sol";
import "../lib/SafeERC20.sol";
import "../lib/EnumerableSet.sol";

library SafeProxy {
    function safeExecute(
        IGmxDepositor gmxDepositor,
        address target,
        uint256 value,
        bytes memory data
    ) internal returns (bytes memory) {
        (bool success, bytes memory returnValue) = gmxDepositor.execute(target, value, data);
        if (!success) assert(false);
        return returnValue;
    }
}

contract GmxProxy {
    using SafeMath for uint256;
    using SafeProxy for IGmxDepositor;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 internal constant BIPS_DIVISOR = 10000;

    address internal constant GMX = 0x62edc0692BD897D2295872a9FFCac5425011c661;
    address internal constant fsGLP = 0x5643F4b25E36478eE1E90418d5343cb6591BcB9d;
    address internal constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;

    IGmxDepositor public immutable gmxDepositor;
    address public immutable gmxRewardRouter;
    address public immutable devAddr;

    address internal immutable gmxRewardTracker;
    address internal immutable glpManager;

    modifier onlyDev() {
        require(msg.sender == devAddr, "GmxProxy::onlyDev");
        _;
    }

    modifier onlyStrategy() {
        require(approvedStrategies.contains(msg.sender), "GmxProxy:onlyStrategy");
        _;
    }

    EnumerableSet.AddressSet private approvedStrategies;

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

    function approveStrategy(address _strategy) external onlyDev {
        approvedStrategies.add(_strategy);
    }

    function isApprovedStrategy(address _strategy) external view returns (bool) {
        return approvedStrategies.contains(_strategy);
    }

    function buyAndStakeGlp(uint256 _amount) external onlyStrategy returns (uint256) {
        IERC20(WAVAX).safeTransfer(address(gmxDepositor), _amount);
        gmxDepositor.safeExecute(WAVAX, 0, abi.encodeWithSignature("approve(address,uint256)", glpManager, _amount));
        bytes memory result = gmxDepositor.safeExecute(
            gmxRewardRouter,
            0,
            abi.encodeWithSignature("mintAndStakeGlp(address,uint256,uint256,uint256)", WAVAX, _amount, 0, 0)
        );
        return toUint256(result, 0);
    }

    function withdrawGlp(uint256 _amount) external onlyStrategy {
        _withdrawGlp(_amount);
    }

    function _withdrawGlp(uint256 _amount) private {
        gmxDepositor.safeExecute(fsGLP, 0, abi.encodeWithSignature("transfer(address,uint256)", msg.sender, _amount));
    }

    function stakeGmx(uint256 _amount) external onlyStrategy {
        IERC20(GMX).safeTransfer(address(gmxDepositor), _amount);
        gmxDepositor.safeExecute(
            GMX,
            0,
            abi.encodeWithSignature("approve(address,uint256)", gmxRewardTracker, _amount)
        );
        gmxDepositor.safeExecute(gmxRewardRouter, 0, abi.encodeWithSignature("stakeGmx(uint256)", _amount));
    }

    function withdrawGmx(uint256 _amount) external onlyStrategy {
        _withdrawGmx(_amount);
    }

    function _withdrawGmx(uint256 _amount) private {
        gmxDepositor.safeExecute(gmxRewardRouter, 0, abi.encodeWithSignature("unstakeGmx(uint256)", _amount));
        gmxDepositor.safeExecute(GMX, 0, abi.encodeWithSignature("transfer(address,uint256)", msg.sender, _amount));
    }

    function emergencyWithdraw(address _token, uint256 _balance) external onlyStrategy {
        if (_token == GMX) {
            _withdrawGmx(_balance);
        } else {
            _withdrawGlp(_balance);
        }
    }

    function _compoundEsGmx() private {
        gmxDepositor.safeExecute(address(gmxRewardRouter), 0, abi.encodeWithSignature("compound()"));
    }

    function claimReward(address rewardTracker) external onlyStrategy {
        gmxDepositor.safeExecute(rewardTracker, 0, abi.encodeWithSignature("claim(address)", msg.sender));
        _compoundEsGmx();
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
