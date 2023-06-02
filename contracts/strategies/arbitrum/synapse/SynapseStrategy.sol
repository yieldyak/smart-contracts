// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../VariableRewardsStrategy.sol";

import "./interfaces/ISynapseSwap.sol";
import "./interfaces/IMiniChefV2.sol";
import "./interfaces/IUniV3Pool.sol";

contract SynapseStrategy is VariableRewardsStrategy {
    using SafeERC20 for IERC20;

    IERC20 private constant SYN = IERC20(0x080F6AEd32Fc474DD5717105Dba5ea57268F46eb);
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;

    address private immutable uniPoolTokenOut;
    bool private immutable zeroForOne;
    uint160 private immutable sqrtPriceLimitX96;

    uint256 public immutable PID;
    IMiniChefV2 public immutable miniChef;

    address public immutable uniV3Pool;
    ISynapseSwap public immutable synapseSwap;
    address public immutable synapseLpTokenIn;
    uint256 public immutable synapseLpTokenIndex;
    uint256 public immutable synapseLpTokenCount;

    address public immutable swapPairSynapseTokenIn;

    struct SynapseStrategySettings {
        address stakingContract;
        uint256 pid;
        address uniV3Pool;
        address swapPairSynapseTokenIn;
        address synapseLpTokenIn;
        address synapseSwap;
        uint256 synapseLpTokenCount;
    }

    constructor(
        SynapseStrategySettings memory _synapseStrategySettings,
        VariableRewardsStrategySettings memory _settings,
        StrategySettings memory _strategySettings
    ) VariableRewardsStrategy(_settings, _strategySettings) {
        miniChef = IMiniChefV2(_synapseStrategySettings.stakingContract);
        PID = _synapseStrategySettings.pid;
        uniV3Pool = _synapseStrategySettings.uniV3Pool;
        swapPairSynapseTokenIn = _synapseStrategySettings.swapPairSynapseTokenIn;
        synapseLpTokenIn = _synapseStrategySettings.synapseLpTokenIn;
        synapseSwap = ISynapseSwap(_synapseStrategySettings.synapseSwap);
        synapseLpTokenCount = _synapseStrategySettings.synapseLpTokenCount;
        synapseLpTokenIndex = synapseSwap.getTokenIndex(synapseLpTokenIn);
        address uniPoolToken0 = IUniV3Pool(uniV3Pool).token0();
        address uniPoolToken1 = IUniV3Pool(uniV3Pool).token1();
        require(uniPoolToken0 == address(SYN) || uniPoolToken1 == address(SYN), "Incompatible pool");
        zeroForOne = true;
        uniPoolTokenOut = zeroForOne ? uniPoolToken1 : uniPoolToken0;
        sqrtPriceLimitX96 = zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1;
    }

    function _depositToStakingContract(uint256 _amount, uint256) internal override {
        IERC20(address(depositToken)).approve(address(miniChef), _amount);
        miniChef.deposit(PID, _amount, address(this));
        IERC20(address(depositToken)).approve(address(miniChef), 0);
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 _withdrawAmount) {
        miniChef.withdraw(PID, _amount, address(this));
        return _amount;
    }

    function _emergencyWithdraw() internal override {
        depositToken.approve(address(miniChef), 0);
        miniChef.emergencyWithdraw(PID, address(this));
    }

    function _pendingRewards() internal view override returns (Reward[] memory) {
        Reward[] memory pendingRewards = new Reward[](1);
        uint256 pendingSYN = miniChef.pendingSynapse(PID, address(this));
        pendingRewards[0] = Reward({reward: address(SYN), amount: pendingSYN});
        return pendingRewards;
    }

    function _getRewards() internal override {
        miniChef.harvest(PID, address(this));
    }

    function totalDeposits() public view override returns (uint256) {
        (uint256 amount,) = miniChef.userInfo(PID, address(this));
        return amount;
    }

    function _convertRewardTokenToDepositToken(uint256 fromAmount) internal override returns (uint256 toAmount) {
        (int256 amount0, int256 amount1) =
            IUniV3Pool(uniV3Pool).swap(address(this), zeroForOne, int256(fromAmount), sqrtPriceLimitX96, "");
        fromAmount = zeroForOne ? uint256(-amount1) : uint256(-amount0);

        if (uniPoolTokenOut != synapseLpTokenIn) {
            fromAmount = DexLibrary.swap(fromAmount, uniPoolTokenOut, synapseLpTokenIn, IPair(swapPairSynapseTokenIn));
        }

        IERC20(synapseLpTokenIn).approve(address(synapseSwap), fromAmount);
        uint256[] memory amounts = new uint256[](synapseLpTokenCount);
        amounts[synapseLpTokenIndex] = fromAmount;
        toAmount = synapseSwap.addLiquidity(amounts, 0, type(uint256).max);
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external {
        require(msg.sender == uniV3Pool);
        rewardToken.safeTransfer(uniV3Pool, zeroForOne ? uint256(amount0Delta) : uint256(amount1Delta));
    }
}
