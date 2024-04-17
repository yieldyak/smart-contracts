// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../../interfaces/IYakStrategy.sol";
import "../../../lib/SafeERC20.sol";
import "../../../lib/SafeMath.sol";
import "./../../../interfaces/ISimpleRouter.sol";

import "./interfaces/IGmxDepositor.sol";
import "./interfaces/IGmxRewardRouter.sol";
import "./interfaces/IGmxRewardTracker.sol";
import "./interfaces/IGmxProxy.sol";
import "./interfaces/IGlpManager.sol";
import "./interfaces/IGmxVault.sol";

library SafeProxy {
    function safeExecute(IGmxDepositor gmxDepositor, address target, uint256 value, bytes memory data)
        internal
        returns (bytes memory)
    {
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
    uint256 internal constant USDG_PRICE_PRECISION = 1e30;

    address internal constant GMX = 0x62edc0692BD897D2295872a9FFCac5425011c661;
    address internal constant fsGLP = 0x5643F4b25E36478eE1E90418d5343cb6591BcB9d;
    address internal constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    address internal constant esGMX = 0xFf1489227BbAAC61a9209A08929E4c2a526DdD17;

    address public devAddr;
    mapping(address => address) public approvedStrategies;

    IGmxDepositor public immutable override gmxDepositor;
    address public immutable override gmxRewardRouter;
    address public immutable glpMinter;

    address internal immutable gmxRewardTracker;
    address internal immutable glpManager;
    address internal immutable vault;
    address internal immutable vaultUtils;
    address internal immutable usdg;

    ISimpleRouter internal immutable simpleRouter;
    uint256 internal immutable MAX_WAVAX_SWAP_AMOUNT;

    modifier onlyDev() {
        require(msg.sender == devAddr, "GmxProxy::onlyDev");
        _;
    }

    modifier onlyStrategy() {
        require(
            approvedStrategies[fsGLP] == msg.sender || approvedStrategies[GMX] == msg.sender, "GmxProxy:onlyGLPStrategy"
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
        address _gmxRewardRouterV2,
        address _simpleRouter,
        uint256 _maxWavaxSwapAmount,
        address _devAddr
    ) {
        require(_gmxDepositor > address(0), "GmxProxy::Invalid depositor address provided");
        require(_gmxRewardRouter > address(0), "GmxProxy::Invalid reward router address provided");
        require(_devAddr > address(0), "GmxProxy::Invalid dev address provided");
        devAddr = _devAddr;
        gmxDepositor = IGmxDepositor(_gmxDepositor);
        gmxRewardRouter = _gmxRewardRouter;
        glpMinter = _gmxRewardRouterV2;
        gmxRewardTracker = IGmxRewardRouter(_gmxRewardRouter).stakedGmxTracker();
        glpManager = IGmxRewardRouter(_gmxRewardRouterV2).glpManager();
        vault = IGlpManager(glpManager).vault();
        usdg = IGmxVault(vault).usdg();
        vaultUtils = address(IGmxVault(vault).vaultUtils());
        simpleRouter = ISimpleRouter(_simpleRouter);
        MAX_WAVAX_SWAP_AMOUNT = _maxWavaxSwapAmount;
    }

    function updateDevAddr(address newValue) public onlyDev {
        require(newValue > address(0), "GmxProxy::Invalid dev address provided");
        devAddr = newValue;
    }

    function approveStrategy(address _strategy) external onlyDev {
        address depositToken = IYakStrategy(_strategy).depositToken();
        require(approvedStrategies[depositToken] == address(0), "GmxProxy::Strategy for deposit token already added");
        approvedStrategies[depositToken] = _strategy;
    }

    function stakeESGMX() external onlyDev {
        gmxDepositor.safeExecute(
            gmxRewardRouter,
            0,
            abi.encodeWithSignature("stakeEsGmx(uint256)", IERC20(esGMX).balanceOf(address(gmxDepositor)))
        );
    }

    function stakedESGMX() public view returns (uint256) {
        return IGmxRewardTracker(gmxRewardTracker).depositBalances(address(gmxDepositor), esGMX);
    }

    function buyAndStakeGlp(uint256 _amount) external override onlyGLPStrategy returns (uint256) {
        address tokenIn = WAVAX;

        if (_amount < MAX_WAVAX_SWAP_AMOUNT) {
            uint256 price = IGmxVault(vault).getMinPrice(WAVAX);
            uint256 usdgAmount = (_amount * price) / USDG_PRICE_PRECISION;
            uint256 feeBasisPoints = type(uint256).max;
            uint256 allWhiteListedTokensLength = IGmxVault(vault).allWhitelistedTokensLength();
            for (uint256 i = 0; i < allWhiteListedTokensLength; i++) {
                address whitelistedToken = IGmxVault(vault).allWhitelistedTokens(i);
                uint256 currentFeeBasisPoints =
                    IGmxVaultUtils(vaultUtils).getBuyUsdgFeeBasisPoints(whitelistedToken, usdgAmount);
                if (currentFeeBasisPoints < feeBasisPoints) {
                    feeBasisPoints = currentFeeBasisPoints;
                    tokenIn = whitelistedToken;
                }
            }

            if (tokenIn != WAVAX) {
                FormattedOffer memory offer = simpleRouter.query(_amount, WAVAX, tokenIn);
                IERC20(WAVAX).approve(address(simpleRouter), _amount);
                _amount = simpleRouter.swap(offer);
            }
        }

        IERC20(tokenIn).safeTransfer(address(gmxDepositor), _amount);
        gmxDepositor.safeExecute(tokenIn, 0, abi.encodeWithSignature("approve(address,uint256)", glpManager, _amount));
        bytes memory result = gmxDepositor.safeExecute(
            glpMinter,
            0,
            abi.encodeWithSignature("mintAndStakeGlp(address,uint256,uint256,uint256)", tokenIn, _amount, 0, 0)
        );
        gmxDepositor.safeExecute(tokenIn, 0, abi.encodeWithSignature("approve(address,uint256)", glpManager, 0));
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
        gmxDepositor.safeExecute(GMX, 0, abi.encodeWithSignature("approve(address,uint256)", gmxRewardTracker, _amount));
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

    function pendingRewards(address _rewardTracker) external view override returns (uint256) {
        address feeGmxTracker = IGmxRewardRouter(gmxRewardRouter).feeGmxTracker();
        if (_rewardTracker == feeGmxTracker) return 0;

        return IGmxRewardTracker(IGmxRewardRouter(gmxRewardRouter).feeGlpTracker()).claimable(address(gmxDepositor))
            + IGmxRewardTracker(feeGmxTracker).claimable(address(gmxDepositor));
    }

    function claimReward(address rewardTracker) external override onlyStrategy {
        address feeGmxTracker = IGmxRewardRouter(gmxRewardRouter).feeGmxTracker();
        if (rewardTracker == feeGmxTracker) return;
        gmxDepositor.safeExecute(
            gmxRewardRouter,
            0,
            abi.encodeWithSignature(
                "handleRewards(bool,bool,bool,bool,bool,bool,bool)", false, false, true, true, true, true, false
            )
        );
        uint256 reward = IERC20(WAVAX).balanceOf(address(gmxDepositor));
        gmxDepositor.safeExecute(WAVAX, 0, abi.encodeWithSignature("transfer(address,uint256)", msg.sender, reward));
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
