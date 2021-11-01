// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "../interfaces/IAvaiPodLeader.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IPair.sol";
import "../lib/DexLibrary.sol";
import "./MasterChefStrategyForLP.sol";

contract AvaiStrategyForLP is MasterChefStrategyForLP {
    using SafeMath for uint256;

    IAvaiPodLeader public podLeader;
    address public nativeRewardToken;
    address public swapPairRewardToken;
    uint256 public depositFeeBips;

    constructor(
        string memory _name,
        address _depositToken,
        address _rewardToken,
        address _nativeRewardToken,
        address _swapPairToken0, // swap rewardToken to token0
        address _swapPairToken1, // swap rewardToken to token1
        address _swapPairRewardToken, // swap nativeRewardToken to rewardToken
        address _stakingRewards,
        uint256 _pid,
        address _timelock,
        uint256 _depositFeeBips,
        uint256 _minTokensToReinvest,
        uint256 _adminFeeBips,
        uint256 _devFeeBips,
        uint256 _reinvestRewardBips
    )
        MasterChefStrategyForLP(
            _name,
            _depositToken,
            _rewardToken,
            _swapPairToken0,
            _swapPairToken1,
            _stakingRewards,
            _timelock,
            _pid,
            _minTokensToReinvest,
            _adminFeeBips,
            _devFeeBips,
            _reinvestRewardBips
        )
    {
        podLeader = IAvaiPodLeader(_stakingRewards);
        depositFeeBips = _depositFeeBips;
        nativeRewardToken = _nativeRewardToken;
        if (nativeRewardToken != address(rewardToken)) {
            swapPairRewardToken = _swapPairRewardToken;
            require(
                DexLibrary.checkSwapPairCompatibility(
                    IPair(swapPairRewardToken),
                    nativeRewardToken,
                    address(rewardToken)
                ),
                "Swap pair does not match reward token and native reward token"
            );
        }
    }

    function _depositMasterchef(uint256 _pid, uint256 _amount) internal override {
        podLeader.deposit(_pid, _amount);
    }

    function _withdrawMasterchef(uint256 _pid, uint256 _amount) internal override {
        podLeader.withdraw(_pid, _amount);
    }

    function _emergencyWithdraw(uint256 _pid) internal override {
        podLeader.emergencyWithdraw(_pid);
    }

    function _pendingRewards(uint256 _pid, address _user) internal view override returns (uint256) {
        if (address(rewardToken) != nativeRewardToken) {
            return
                DexLibrary.estimateConversionThroughPair(
                    podLeader.pendingRewards(_pid, _user),
                    nativeRewardToken,
                    address(rewardToken),
                    IPair(swapPairRewardToken)
                );
        } else {
            return podLeader.pendingRewards(_pid, _user);
        }
    }

    function _getRewards(uint256 _pid) internal override {
        podLeader.deposit(_pid, 0);
        if (address(rewardToken) != nativeRewardToken) {
            DexLibrary.swap(
                IERC20(nativeRewardToken).balanceOf(address(this)),
                nativeRewardToken,
                address(rewardToken),
                IPair(swapPairRewardToken)
            );
        }
    }

    function _getDepositBalance(uint256 pid, address user) internal view override returns (uint256 amount) {
        (amount, ) = podLeader.userInfo(pid, user);
    }

    function setDepositFeeBips(uint256 _depositFeeBips) external onlyOwner {
        depositFeeBips = _depositFeeBips;
    }

    function _getDepositFeeBips(uint256 pid) internal view override returns (uint256) {
        return depositFeeBips;
    }

    function _getWithdrawFeeBips(uint256 pid) internal view override returns (uint256) {
        return 0;
    }

    function _bip() internal view override returns (uint256) {
        return 10000;
    }
}
