// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./../../VariableRewardsStrategy.sol";

import "./interfaces/INFTPool.sol";
import "./interfaces/ICamelotVoterProxy.sol";
import "./interfaces/ICamelotLP.sol";
import "./interfaces/INitroPool.sol";

contract CamelotStrategy is VariableRewardsStrategy {
    using SafeERC20 for IERC20;

    struct CamelotStrategySettings {
        address nftPool;
        uint256 positionId;
        address nitroPool;
        address swapPairToken0;
        uint256 swapFeeToken0;
        address swapPairToken1;
        uint256 swapFeeToken1;
        address voterProxy;
    }

    address public constant GRAIL = 0x3d9907F9a368ad0a51Be60f7Da3b97cf940982D8;

    address public immutable pool;
    uint256 public immutable positionId;

    address public nitroPool;
    ICamelotVoterProxy public proxy;
    address public swapPairToken0;
    address public swapPairToken1;
    uint256 public swapFeeToken0;
    uint256 public swapFeeToken1;

    constructor(
        CamelotStrategySettings memory _camelotStrategySettings,
        VariableRewardsStrategySettings memory _variableRewardsStrategySettings,
        StrategySettings memory _strategySettings
    ) VariableRewardsStrategy(_variableRewardsStrategySettings, _strategySettings) {
        pool = _camelotStrategySettings.nftPool;
        nitroPool = _camelotStrategySettings.nitroPool;
        positionId = _camelotStrategySettings.positionId;
        swapPairToken0 = _camelotStrategySettings.swapPairToken0;
        swapPairToken1 = _camelotStrategySettings.swapPairToken1;
        swapFeeToken0 = _camelotStrategySettings.swapFeeToken0;
        swapFeeToken1 = _camelotStrategySettings.swapFeeToken1;
        proxy = ICamelotVoterProxy(_camelotStrategySettings.voterProxy);
    }

    function setPlatypusVoterProxy(address _voterProxy) external onlyOwner {
        proxy = ICamelotVoterProxy(_voterProxy);
    }

    /**
     * @notice Needed because camelot pairs have mutable fees
     */
    function updateSwapPairs(
        address _swapPairToken0,
        address _swapPairToken1,
        uint256 _swapFeeToken0,
        uint256 _swapFeeToken1
    ) external onlyDev {
        if (_swapPairToken0 > address(0)) {
            swapPairToken0 = _swapPairToken0;
            swapFeeToken0 = _swapFeeToken0;
        }
        if (_swapPairToken1 > address(0)) {
            swapPairToken1 = _swapPairToken1;
            swapFeeToken1 = _swapFeeToken1;
        }
    }

    /**
     * @notice Updates nitro pool
     * @dev Use NitroPoolFactory.nftPoolPublishedNitroPoolsLength and getNftPoolPublishedNitroPool to find a suitable nitro pool
     * @param _nitroPoolIndex Relativ index for this NFTPool
     * @param _useNewNitroPool Pass false if there is no nitro pool available anymore
     */
    function updateNitroPool(uint256 _nitroPoolIndex, bool _useNewNitroPool) external onlyDev {
        nitroPool = proxy.updateNitroPool(positionId, nitroPool, pool, _useNewNitroPool, _nitroPoolIndex);
    }

    /**
     * @notice Failsafe for when selected nitro pool has ended and would block withdrawals
     */
    function withdrawFromEndedNitroPool() external {
        (, , , uint256 depositEndTime, , , , , ) = INitroPool(nitroPool).settings();
        require(
            depositEndTime > 0 && depositEndTime < block.timestamp,
            "CamelotStrategy::withdrawFromNitroPool not allowed"
        );
        proxy.updateNitroPool(positionId, nitroPool, pool, false, 0);
        nitroPool = address(0);
    }

    function _depositToStakingContract(uint256 _amount, uint256) internal override {
        proxy.claimReward(positionId, pool, nitroPool);
        depositToken.safeTransfer(address(proxy.voter()), _amount);
        proxy.deposit(positionId, pool, address(depositToken), _amount);
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 withdrawAmount) {
        proxy.claimReward(positionId, pool, nitroPool);
        proxy.withdraw(positionId, pool, nitroPool, address(depositToken), _amount);
        return _amount;
    }

    function _pendingRewards() internal view virtual override returns (Reward[] memory) {
        return proxy.pendingRewards(positionId, pool, nitroPool);
    }

    function _getRewards() internal virtual override {
        proxy.claimReward(positionId, pool, nitroPool);
    }

    function _convertRewardTokenToDepositToken(uint256 fromAmount) internal override returns (uint256 toAmount) {
        toAmount = DexLibrary.convertRewardTokensToDepositTokens(
            fromAmount,
            address(rewardToken),
            address(depositToken),
            IPair(swapPairToken0),
            swapFeeToken0,
            IPair(swapPairToken1),
            swapFeeToken1
        );
    }

    function totalDeposits() public view override returns (uint256) {
        uint256 depositBalance = proxy.poolBalance(positionId, pool);
        return depositBalance;
    }

    function _emergencyWithdraw() internal override {
        proxy.emergencyWithdraw(positionId, pool, nitroPool, address(depositToken));
    }
}
