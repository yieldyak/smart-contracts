// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./../../VariableRewardsStrategy.sol";
import "./../../../interfaces/IERC721Receiver.sol";

import "./interfaces/IGauge.sol";
import "./interfaces/IMaNFT.sol";

contract ChronosStrategy is VariableRewardsStrategy, IERC721Receiver {
    using SafeERC20 for IERC20;

    struct ChronosStrategySettings {
        address gauge;
        address swapPairToken0;
        uint256 swapFeeToken0;
        address swapPairToken1;
        uint256 swapFeeToken1;
        address boosterFeeCollector;
    }

    address private constant CHR = 0x15b2fb8f08E4Ac1Ce019EADAe02eE92AeDF06851;

    IGauge public immutable gauge;
    IMaNFT public immutable nft;

    address public swapPairToken0;
    address public swapPairToken1;
    uint256 public swapFeeToken0;
    uint256 public swapFeeToken1;

    uint256[] public tokenIds;

    constructor(
        ChronosStrategySettings memory _glacierStrategySettings,
        VariableRewardsStrategySettings memory _variableRewardsStrategySettings,
        StrategySettings memory _strategySettings
    ) VariableRewardsStrategy(_variableRewardsStrategySettings, _strategySettings) {
        gauge = IGauge(_glacierStrategySettings.gauge);
        nft = IMaNFT(IGauge(_glacierStrategySettings.gauge).maNFTs());
        swapPairToken0 = _glacierStrategySettings.swapPairToken0;
        swapPairToken1 = _glacierStrategySettings.swapPairToken1;
        swapFeeToken0 = _glacierStrategySettings.swapFeeToken0;
        swapFeeToken1 = _glacierStrategySettings.swapFeeToken1;
    }

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

    function _depositToStakingContract(uint256 _amount, uint256) internal override {
        IERC20(depositToken).approve(address(gauge), _amount);
        mergeNFTs(gauge.deposit(_amount));
    }

    function _withdrawFromStakingContract(uint256 _amount) internal override returns (uint256 withdrawAmount) {
        uint256 index = tokenIds.length - 1;
        uint256 remaining = _amount;
        uint256 balanceOfToken;
        while (remaining >= balanceOfToken) {
            uint256 tokenId = tokenIds[index];
            balanceOfToken = gauge.balanceOfToken(tokenId);
            tokenIds.pop();
            if (remaining >= balanceOfToken) {
                gauge.withdrawAndHarvest(tokenId);
                remaining -= balanceOfToken;
                if (index > 0) index--;
            } else {
                uint256 nextId = nft.tokenIdView();
                nextId++;
                uint256[] memory amounts = new uint[](2);
                amounts[0] = balanceOfToken - remaining;
                amounts[1] = remaining;
                gauge.harvestAndSplit(amounts, tokenId);
                gauge.withdrawAndHarvest(nextId + 1);
                tokenIds.push(nextId);
                remaining = 0;
            }
        }
        return _amount;
    }

    function mergeNFTs(uint256 tokenId) internal {
        uint256 lastIndex = tokenIds.length;
        uint256 lastEpoch;
        uint256 lastId;
        if (lastIndex > 0) {
            lastId = tokenIds[lastIndex - 1];
            lastEpoch = gauge._depositEpoch(lastId);
        }
        if (lastEpoch == block.timestamp / 1 weeks) {
            gauge.harvestAndMerge(tokenId, lastId);
        } else {
            tokenIds.push(tokenId);
        }
    }

    function _pendingRewards() internal view virtual override returns (Reward[] memory) {
        Reward[] memory rewards = new Reward[](1);
        rewards[0] = Reward({reward: CHR, amount: gauge.earned(address(this))});
        return rewards;
    }

    function _getRewards() internal virtual override {
        gauge.getAllReward();
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
        return gauge.balanceOf(address(this));
    }

    function _emergencyWithdraw() internal override {
        gauge.withdrawAndHarvestAll();
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
