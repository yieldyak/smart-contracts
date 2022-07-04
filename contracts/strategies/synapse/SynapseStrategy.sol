// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../VariableRewardsStrategy.sol";

import "./interfaces/ISwapFlashLoan.sol";
import "./interfaces/IMiniChefV2.sol";

contract SynapseStrategy is VariableRewardsStrategy {
    IERC20 private constant SYN = IERC20(0x1f1E7c893855525b303f99bDF5c3c05Be09ca251);

    uint256 public immutable PID;

    ISwapFlashLoan public immutable synapseSwap;
    IMiniChefV2 public immutable miniChef;

    address public immutable swapDepositToken;
    address public immutable swapPairDepositToken;
    uint256 public immutable tokenIndex;
    uint256 public immutable tokenCount;

    constructor(
        string memory _name,
        address _depositToken,
        RewardSwapPairs[] memory _rewardSwapPairs,
        address _swapDepositToken,
        address _swapPairDepositToken,
        uint256 _tokenCount,
        address _swapContract,
        address _stakingContract,
        uint256 _pid,
        address _timelock,
        StrategySettings memory _strategySettings
    ) VariableRewardsStrategy(_name, _depositToken, _rewardSwapPairs, _timelock, _strategySettings) {
        PID = _pid;
        swapDepositToken = _swapDepositToken;
        swapPairDepositToken = _swapPairDepositToken;
        synapseSwap = ISwapFlashLoan(_swapContract);
        miniChef = IMiniChefV2(_stakingContract);
        tokenIndex = ISwapFlashLoan(_swapContract).getTokenIndex(_swapDepositToken);
        tokenCount = _tokenCount;
    }

    function _depositToStakingContract(uint256 _amount) internal override {
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
        (uint256 amount, ) = miniChef.userInfo(PID, address(this));
        return amount;
    }

    function _convertRewardTokenToDepositToken(uint256 fromAmount) internal override returns (uint256 toAmount) {
        uint256 amount = DexLibrary.swap(fromAmount, address(WAVAX), swapDepositToken, IPair(swapPairDepositToken));

        IERC20(swapDepositToken).approve(address(synapseSwap), amount);
        uint256[] memory amounts = new uint256[](tokenCount);
        amounts[tokenIndex] = amount;
        toAmount = synapseSwap.addLiquidity(amounts, 0, type(uint256).max);
        IERC20(swapDepositToken).approve(address(synapseSwap), 0);
    }
}
