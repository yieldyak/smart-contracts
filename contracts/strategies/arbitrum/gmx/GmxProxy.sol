// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../../interfaces/IYakStrategy.sol";
import "../../../lib/SafeERC20.sol";
import "../../../lib/DexLibrary.sol";

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
    using SafeProxy for IGmxDepositor;
    using SafeERC20 for IERC20;

    uint256 internal constant BIPS_DIVISOR = 10000;

    address internal constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address internal constant USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address internal constant GMX = 0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a;
    address internal constant sGLP = 0x5402B5F40310bDED796c7D0F3FF6683f5C0cFfdf;
    address internal constant esGMX = 0xf42Ae1D54fd613C9bb14810b0588FaAa09a426cA;
    uint256 internal constant USDG_PRICE_PRECISION = 1e30;

    address public devAddr;
    address public approvedStrategy;

    IGmxDepositor public immutable override gmxDepositor;
    address public immutable override gmxRewardRouter;
    address public immutable glpMinter;

    address internal immutable gmxRewardTracker;
    address internal immutable glpRewardTracker;
    address internal immutable glpManager;
    address internal immutable vault;
    address internal immutable usdg;
    address internal immutable wethUsdcPair;
    uint256 internal immutable swapFee;

    modifier onlyDev() {
        require(msg.sender == devAddr, "GmxProxy::onlyDev");
        _;
    }

    modifier onlyStrategy() {
        require(approvedStrategy == msg.sender, "GmxProxy:onlyStrategy");
        _;
    }

    constructor(
        address _gmxDepositor,
        address _gmxRewardRouter,
        address _gmxRewardRouterV2,
        address _wethUsdcPair,
        uint256 _swapFee,
        address _devAddr
    ) {
        require(_devAddr > address(0), "GmxProxy::Invalid dev address provided");
        devAddr = _devAddr;
        gmxDepositor = IGmxDepositor(_gmxDepositor);
        gmxRewardRouter = _gmxRewardRouter;
        glpMinter = _gmxRewardRouterV2;
        gmxRewardTracker = IGmxRewardRouter(_gmxRewardRouter).stakedGmxTracker();
        glpRewardTracker = IGmxRewardRouter(_gmxRewardRouter).feeGlpTracker();
        glpManager = IGmxRewardRouter(_gmxRewardRouterV2).glpManager();
        vault = IGlpManager(glpManager).vault();
        usdg = IGmxVault(vault).usdg();
        wethUsdcPair = _wethUsdcPair;
        swapFee = _swapFee;
    }

    function updateDevAddr(address newValue) public onlyDev {
        require(newValue > address(0), "GmxProxy::Invalid dev address provided");
        devAddr = newValue;
    }

    function approveStrategy(address _strategy) external onlyDev {
        require(approvedStrategy == address(0), "GmxProxy::Strategy already defined");
        approvedStrategy = _strategy;
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

    function vaultHasEthCapacity(uint256 _amountIn) internal view returns (bool) {
        uint256 price = IGmxVault(vault).getMinPrice(WETH);
        uint256 usdgAmount = (_amountIn * price) / USDG_PRICE_PRECISION;
        usdgAmount = IGmxVault(vault).adjustForDecimals(usdgAmount, WETH, usdg);
        uint256 vaultUsdgAmount = IGmxVault(vault).usdgAmounts(WETH);
        uint256 maxUsdgAmount = IGmxVault(vault).maxUsdgAmounts(WETH);
        return maxUsdgAmount == 0 || vaultUsdgAmount + usdgAmount < maxUsdgAmount;
    }

    function swapToUSDC(uint256 _amount) internal returns (uint256) {
        return DexLibrary.swap(_amount, WETH, USDC, IPair(wethUsdcPair), swapFee);
    }

    function buyAndStakeGlp(uint256 _amount) external override onlyStrategy returns (uint256) {
        bool sufficientEthCapacity = vaultHasEthCapacity(_amount);
        address token = sufficientEthCapacity ? WETH : USDC;
        _amount = sufficientEthCapacity ? _amount : swapToUSDC(_amount);

        IERC20(token).transfer(address(gmxDepositor), _amount);

        gmxDepositor.safeExecute(token, 0, abi.encodeWithSignature("approve(address,uint256)", glpManager, _amount));
        bytes memory result = gmxDepositor.safeExecute(
            glpMinter,
            0,
            abi.encodeWithSignature("mintAndStakeGlp(address,uint256,uint256,uint256)", token, _amount, 0, 0)
        );
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
                "handleRewards(bool,bool,bool,bool,bool,bool,bool)", false, false, true, true, true, true, false
            )
        );
        uint256 reward = IERC20(WETH).balanceOf(address(gmxDepositor));
        gmxDepositor.safeExecute(WETH, 0, abi.encodeWithSignature("transfer(address,uint256)", msg.sender, reward));
    }

    function totalDeposits() external view override returns (uint256) {
        return IGmxRewardTracker(glpRewardTracker).stakedAmounts(address(gmxDepositor));
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
