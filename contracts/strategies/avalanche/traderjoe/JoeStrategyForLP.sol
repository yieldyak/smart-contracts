// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../MasterChefStrategyForLP.sol";
import "../../../interfaces/IERC20.sol";
import "../../../interfaces/IPair.sol";
import "../../../lib/DexLibrary.sol";

import "./interfaces/IJoeChef.sol";

contract JoeStrategyForLP is MasterChefStrategyForLP {
    using SafeMath for uint256;

    IJoeChef public joeChef;
    address public swapPairRewardToken;

    constructor(
        string memory _name,
        address _nativeRewardToken,
        SwapPairs memory _swapPairs,
        address _stakingRewards,
        uint256 _pid,
        address _timelock,
        StrategySettings memory _strategySettings
    ) MasterChefStrategyForLP(_name, _nativeRewardToken, _swapPairs, _timelock, _pid, _strategySettings) {
        joeChef = IJoeChef(_stakingRewards);
    }

    receive() external payable {
        (, , , , address rewarder) = joeChef.poolInfo(PID);
        require(
            msg.sender == rewarder ||
                msg.sender == address(joeChef) ||
                msg.sender == owner() ||
                msg.sender == address(devAddr),
            "not allowed"
        );
    }

    function _depositMasterchef(uint256 _pid, uint256 _amount) internal override {
        depositToken.approve(address(joeChef), _amount);
        joeChef.deposit(_pid, _amount);
    }

    function _withdrawMasterchef(uint256 _pid, uint256 _amount) internal override {
        joeChef.withdraw(_pid, _amount);
    }

    function _emergencyWithdraw(uint256 _pid) internal override {
        depositToken.approve(address(joeChef), 0);
        joeChef.emergencyWithdraw(_pid);
    }

    /**
     * @notice Returns pending rewards
     * @dev `rewarder` distributions are not considered
     */
    function _pendingRewards(uint256 _pid, address _user)
        internal
        view
        override
        returns (
            uint256,
            uint256,
            address
        )
    {
        (uint256 pendingJoe, address bonusTokenAddress, , uint256 pendingBonusToken) = joeChef.pendingTokens(
            _pid,
            _user
        );
        return (pendingJoe, pendingBonusToken, bonusTokenAddress);
    }

    function _getRewards(uint256 _pid) internal override {
        joeChef.deposit(_pid, 0);
    }

    function _getDepositBalance(uint256 _pid, address _user) internal view override returns (uint256 amount) {
        (amount, ) = joeChef.userInfo(_pid, _user);
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
