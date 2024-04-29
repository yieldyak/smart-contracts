// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./../../../interfaces/IYakStrategy.sol";
import "./../../../interfaces/IERC20.sol";
import "./../../../lib/SafeERC20.sol";

import "./interfaces/IPendleVoter.sol";
import "./interfaces/IPendleRouter.sol";
import "./interfaces/IPendleMarketLP.sol";
import "./lib/PMath.sol";

library SafeProxy {
    function safeExecute(IPendleVoter voter, address target, uint256 value, bytes memory data)
        internal
        returns (bytes memory)
    {
        (bool success, bytes memory returnValue) = voter.execute(target, value, data);
        if (!success) revert("PendleProxy::safeExecute failed");
        return returnValue;
    }
}

contract PendleProxy {
    using SafeProxy for IPendleVoter;
    using SafeERC20 for IERC20;
    using PMath for uint256;

    struct Reward {
        address reward;
        uint256 amount;
    }

    uint256 internal constant BIPS_DIVISOR = 10000;
    uint128 internal constant INITIAL_REWARD_INDEX = 1;

    address internal immutable PENDLE;

    address public devAddr;
    IPendleVoter public immutable voter;
    address public immutable pendleRouter;

    // deposit token => strategy
    mapping(address => address) public approvedStrategies;
    uint256 boostFeeBips;
    address boostFeeReceiver;

    modifier onlyDev() {
        require(msg.sender == devAddr, "PendleProxy::onlyDev");
        _;
    }

    modifier onlyStrategy(address _depositToken) {
        require(approvedStrategies[_depositToken] == msg.sender, "PendleProxy::onlyStrategy");
        _;
    }

    constructor(
        address _voter,
        address _devAddr,
        address _pendleRouter,
        uint256 _boostFeeBips,
        address _boostFeeReceiver,
        address _pendle
    ) {
        require(_devAddr > address(0), "PendleProxy::Invalid dev address provided");
        devAddr = _devAddr;
        voter = IPendleVoter(_voter);
        pendleRouter = _pendleRouter;
        boostFeeBips = _boostFeeBips;
        boostFeeReceiver = _boostFeeReceiver;
        PENDLE = _pendle;
    }

    /**
     * @notice Update devAddr
     * @param newValue address
     */
    function updateDevAddr(address newValue) external onlyDev {
        devAddr = newValue;
    }

    /**
     * @notice Add an approved strategy
     * @dev Very sensitive, restricted to devAddr
     * @dev Can only be set once per deposit token (reported by the strategy)
     * @param _strategy address
     */
    function approveStrategy(address _strategy) public onlyDev {
        address depositToken = IYakStrategy(_strategy).depositToken();
        require(approvedStrategies[depositToken] == address(0), "PendleProxy::Strategy for deposit token already added");
        approvedStrategies[depositToken] = _strategy;
    }

    /**
     * @notice Update optional boost fee settins
     * @param _boostFeeBips Boost fee bips, check BIPS_DIVISOR
     */
    function updateBoostFee(uint256 _boostFeeBips) external onlyDev {
        require(_boostFeeBips < BIPS_DIVISOR, "PendleProxy::Invalid boost fee");
        boostFeeBips = _boostFeeBips;
    }

    function depositToStakingContract(address _token, uint256 _amount) external onlyStrategy(_token) {
        IERC20(_token).safeTransferFrom(msg.sender, address(voter), _amount);
    }

    function withdrawFromStakingContract(address _token, uint256 _amount) external onlyStrategy(_token) {
        voter.safeExecute(_token, 0, abi.encodeWithSelector(IERC20.transfer.selector, msg.sender, _amount));
    }

    function pendingRewards(address _token) public view returns (Reward[] memory) {
        address[] memory rewardTokens = IPendleMarketLP(_token).getRewardTokens();
        Reward[] memory rewards = new Reward[](rewardTokens.length);
        if (rewardTokens.length == 0) return rewards;

        uint256 totalShares = IPendleMarketLP(_token).totalActiveSupply();

        for (uint256 i = 0; i < rewardTokens.length; ++i) {
            address token = rewardTokens[i];
            (uint256 index, uint256 lastBalance) = IPendleMarketLP(_token).rewardState(token);
            uint256 totalAccrued = IERC20(token).balanceOf(_token) - lastBalance;

            if (index == 0) index = INITIAL_REWARD_INDEX;
            if (totalShares != 0) index += totalAccrued.divDown(totalShares);

            (uint128 userIndex, uint128 accrued) = IPendleMarketLP(_token).userReward(token, address(voter));

            if (userIndex == 0) {
                userIndex = INITIAL_REWARD_INDEX;
            }
            if (userIndex == index) {
                rewards[i] = Reward({reward: token, amount: 0});
            } else {
                uint256 userShares = IPendleMarketLP(_token).activeBalance(address(voter));
                uint256 deltaIndex = index - userIndex;
                uint256 rewardDelta = userShares.mulDown(deltaIndex);
                uint256 rewardAccrued = accrued + rewardDelta;

                rewards[i] = Reward({reward: token, amount: rewardAccrued - _calculateBoostFee(token, rewardAccrued)});
            }
        }
        return rewards;
    }

    function getRewards(address _token) public onlyStrategy(_token) {
        voter.safeExecute(_token, 0, abi.encodeWithSelector(IPendleMarketLP.redeemRewards.selector, address(voter)));
        address[] memory rewardTokens = IPendleMarketLP(_token).getRewardTokens();
        for (uint256 i; i < rewardTokens.length; i++) {
            uint256 amount = IERC20(rewardTokens[i]).balanceOf(address(voter));

            uint256 boostFee = _calculateBoostFee(rewardTokens[i], amount);
            if (rewardTokens[i] == PENDLE) {
                voter.safeExecute(
                    rewardTokens[i], 0, abi.encodeWithSelector(IERC20.transfer.selector, msg.sender, boostFee)
                );
            }

            voter.safeExecute(
                rewardTokens[i], 0, abi.encodeWithSelector(IERC20.transfer.selector, msg.sender, amount - boostFee)
            );
        }
    }

    function _calculateBoostFee(address _token, uint256 _amount) internal view returns (uint256 boostFee) {
        if (_token == PENDLE) {
            return (_amount * boostFeeBips) / BIPS_DIVISOR;
        }
    }

    function totalDeposits(address _token) external view returns (uint256) {
        return IERC20(_token).balanceOf(address(voter));
    }

    function emergencyWithdraw(address _token) external onlyStrategy(_token) {
        voter.safeExecute(
            _token,
            0,
            abi.encodeWithSelector(IERC20.transfer.selector, msg.sender, IERC20(_token).balanceOf(address(voter)))
        );
    }
}
