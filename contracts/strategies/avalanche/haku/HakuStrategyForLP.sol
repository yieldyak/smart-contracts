// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../../MasterChefStrategyForLP.sol";

import "./interfaces/IHakuChef.sol";

contract HakuStrategyForLP is MasterChefStrategyForLP {
    using SafeMath for uint256;

    IHakuChef public hakuChef;
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
        hakuChef = IHakuChef(_stakingRewards);
    }

    function _depositMasterchef(uint256 _pid, uint256 _amount) internal override {
        depositToken.approve(address(hakuChef), _amount);
        hakuChef.deposit(_pid, _amount);
    }

    function _withdrawMasterchef(uint256 _pid, uint256 _amount) internal override {
        hakuChef.withdraw(_pid, _amount);
    }

    function _emergencyWithdraw(uint256 _pid) internal override {
        depositToken.approve(address(hakuChef), 0);
        hakuChef.emergencyWithdraw(_pid);
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
        uint256 pendingHaku = hakuChef.pendingCake(_pid, _user);
        return (pendingHaku, 0, address(0));
    }

    function _getRewards(uint256 _pid) internal override {
        hakuChef.deposit(_pid, 0);
    }

    function _getDepositBalance(uint256 _pid, address _user) internal view override returns (uint256 amount) {
        (amount, ) = hakuChef.userInfo(_pid, _user);
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
