// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../MasterChefStrategyForLP.sol";
import "../../../lib/SafeERC20.sol";

import "./interfaces/IJoeChef.sol";
import "./interfaces/IJoeVoterProxy.sol";

contract BoostedJoeStrategyForLP is MasterChefStrategyForLP {
    using SafeERC20 for IERC20;

    address public stakingContract;
    IJoeVoterProxy public proxy;
    address public swapPairRewardToken;

    constructor(
        string memory _name,
        address _nativeRewardToken,
        SwapPairs memory _swapPairs,
        address _stakingContract,
        uint256 _pid,
        address _voterProxy,
        address _timelock,
        StrategySettings memory _strategySettings
    ) MasterChefStrategyForLP(_name, _nativeRewardToken, _swapPairs, _timelock, _pid, _strategySettings) {
        stakingContract = _stakingContract;
        proxy = IJoeVoterProxy(_voterProxy);
    }

    function _depositMasterchef(uint256 _pid, uint256 _amount) internal override {
        depositToken.safeTransfer(address(proxy), _amount);
        proxy.deposit(_pid, stakingContract, address(depositToken), _amount);
        proxy.distributeReward(_pid, stakingContract, address(extraToken));
    }

    function _withdrawMasterchef(uint256 _pid, uint256 _amount) internal override {
        proxy.withdraw(_pid, stakingContract, address(depositToken), _amount);
        proxy.distributeReward(_pid, stakingContract, address(extraToken));
    }

    function _emergencyWithdraw(uint256 _pid) internal override {
        depositToken.approve(address(proxy), 0);
        proxy.emergencyWithdraw(_pid, stakingContract, address(depositToken));
    }

    /**
     * @notice Returns pending rewards
     * @dev `rewarder` distributions are not considered
     */
    function _pendingRewards(
        uint256 _pid,
        address /*_user*/
    )
        internal
        view
        override
        returns (
            uint256,
            uint256,
            address
        )
    {
        (uint256 pendingJoe, address bonusTokenAddress, uint256 pendingBonusToken) = proxy.pendingRewards(
            stakingContract,
            _pid
        );
        return (pendingJoe, pendingBonusToken, bonusTokenAddress);
    }

    function _getRewards(uint256 _pid) internal override {
        proxy.claimReward(_pid, stakingContract, address(extraToken));
    }

    function _getDepositBalance(
        uint256 _pid,
        address /*_user*/
    ) internal view override returns (uint256 amount) {
        return proxy.poolBalance(stakingContract, _pid);
    }

    function _getDepositFeeBips(uint256) internal pure override returns (uint256) {
        return 0;
    }

    function _getWithdrawFeeBips(uint256) internal pure override returns (uint256) {
        return 0;
    }

    function _bip() internal pure override returns (uint256) {
        return 10000;
    }
}
