// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../../lib/SafeERC20.sol";
import "../../../lib/SafeMath.sol";

import "./interfaces/IEchidnaVoter.sol";
import "./interfaces/IEchidnaVoterProxy.sol";
import "./interfaces/IEchidnaMasterChef.sol";
import "./interfaces/IVeEcdRewardPool.sol";
import "./interfaces/IEchidnaStrategyForLP.sol";

library SafeProxy {
    function safeExecute(
        IEchidnaVoter voter,
        address target,
        uint256 value,
        bytes memory data
    ) internal returns (bytes memory) {
        (bool success, bytes memory returnValue) = voter.execute(target, value, data);
        if (!success) revert("EchidnaVoterProxy::safeExecute failed");
        return returnValue;
    }
}

/**
 * @notice EchidnaVoterProxy is an upgradable contract.
 * Strategies interact with EchidnaVoterProxy and
 * EchidnaVoterProxy interacts with EchidnaVoter.
 * @dev For accounting reasons, there is one approved
 * strategy per Masterchef PID. In case of upgrade,
 * use a new proxy.
 */
contract EchidnaVoterProxy is IEchidnaVoterProxy {
    using SafeMath for uint256;
    using SafeProxy for IEchidnaVoter;
    using SafeERC20 for IERC20;

    uint256 internal constant BIPS_DIVISOR = 10000;
    address private constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    address private constant ECD = 0xeb8343D5284CaEc921F035207ca94DB6BAaaCBcd;
    IERC20 private constant PTP = IERC20(0x22d4002028f537599bE9f666d1c4Fa138522f9c8);

    address public constant veEcdRewardPool = 0x0546A4c8E3bC4BF8CC0B44ABF3bA5E7D280bbbAe;
    IEchidnaVoter public immutable voter;
    address public devAddr;
    uint256 public boosterFee;
    address public boosterFeeReceiver;

    // staking contract => pid => strategy
    mapping(address => mapping(uint256 => address)) private approvedStrategies;

    modifier onlyDev() {
        require(msg.sender == devAddr, "EchidnaVoterProxy::onlyDev");
        _;
    }

    modifier onlyStrategy(address _stakingContract, uint256 _pid) {
        require(approvedStrategies[_stakingContract][_pid] == msg.sender, "EchidnaVoterProxy::onlyStrategy");
        _;
    }

    constructor(
        address _voter,
        address _devAddr,
        uint256 _boosterFeeBips,
        address _boosterFeeReceiver
    ) {
        devAddr = _devAddr;
        voter = IEchidnaVoter(_voter);
        boosterFee = _boosterFeeBips;
        boosterFeeReceiver = _boosterFeeReceiver;
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
     * @dev Can only be set once per PID and staking contract (reported by the strategy)
     * @param _stakingContract address
     * @param _strategy address
     */
    function approveStrategy(address _stakingContract, address _strategy) external override onlyDev {
        uint256 pid = IEchidnaStrategyForLP(_strategy).PID();
        require(
            approvedStrategies[_stakingContract][pid] == address(0),
            "EchidnaVoterProxy::Strategy for PID already added"
        );
        approvedStrategies[_stakingContract][pid] = _strategy;
    }

    /**
     * @notice Update booster fee
     * @dev Restricted to devAddr
     * @param _boosterFeeBips new fee in bips (1% = 100 bips)
     */
    function setBoosterFee(uint256 _boosterFeeBips) external onlyDev {
        boosterFee = _boosterFeeBips;
    }

    /**
     * @notice Update booster fee receiver
     * @dev Restricted to devAddr
     * @param _boosterFeeReceiver address
     */
    function setBoosterFeeReceiver(address _boosterFeeReceiver) external onlyDev {
        boosterFeeReceiver = _boosterFeeReceiver;
    }

    /**
     * @notice Deposit function
     * @dev Restricted to strategy with _pid
     * @param _pid PID
     * @param _stakingContract Masterchef
     * @param _token Deposit asset
     * @param _amount deposit amount
     */
    function deposit(
        uint256 _pid,
        address _stakingContract,
        address _token,
        uint256 _amount
    ) external override onlyStrategy(_stakingContract, _pid) {
        IERC20(_token).safeTransfer(address(voter), _amount);
        voter.safeExecute(_token, 0, abi.encodeWithSignature("approve(address,uint256)", _stakingContract, _amount));
        voter.safeExecute(_stakingContract, 0, abi.encodeWithSignature("deposit(uint256,uint256)", _pid, _amount));
        voter.safeExecute(_token, 0, abi.encodeWithSignature("approve(address,uint256)", _stakingContract, 0));
    }

    /**
     * @notice Withdraw function
     * @dev Restricted to strategy with _pid
     * @param _pid PID
     * @param _stakingContract Masterchef
     * @param _token Deposit asset
     * @param _amount withdraw amount
     */
    function withdraw(
        uint256 _pid,
        address _stakingContract,
        address _token,
        uint256 _amount
    ) external override onlyStrategy(_stakingContract, _pid) {
        voter.safeExecute(_stakingContract, 0, abi.encodeWithSignature("withdraw(uint256,uint256)", _pid, _amount));
        voter.safeExecute(_token, 0, abi.encodeWithSignature("transfer(address,uint256)", msg.sender, _amount));
    }

    /**
     * @notice Emergency withdraw function
     * @dev Restricted to strategy with _pid
     * @param _pid PID
     * @param _stakingContract Masterchef
     * @param _token Deposit asset
     */
    function emergencyWithdraw(
        uint256 _pid,
        address _stakingContract,
        address _token
    ) external override onlyStrategy(_stakingContract, _pid) {
        voter.safeExecute(_stakingContract, 0, abi.encodeWithSignature("emergencyWithdraw(uint256)", _pid));
        uint256 balance = IERC20(_token).balanceOf(address(voter));
        voter.safeExecute(_token, 0, abi.encodeWithSignature("transfer(address,uint256)", msg.sender, balance));
    }

    /**
     * @notice Pending rewards matching interface for strategy
     * @param _stakingContract Masterchef
     * @param _pid PID
     */
    function pendingRewards(address _stakingContract, uint256 _pid)
        external
        view
        override
        returns (uint256 pendingECD, uint256 pendingPTP)
    {
        pendingECD = IEchidnaMasterChef(_stakingContract).pendingEcd(_pid, address(voter));
        pendingECD = pendingECD.sub(_calculateBoostFee(pendingECD));
        pendingPTP = IVeEcdRewardPool(veEcdRewardPool).earned(address(voter));
    }

    /**
     * @notice Pool balance
     * @param _stakingContract Masterchef
     * @param _pid PID
     * @return balance in depositToken
     */
    function poolBalance(address _stakingContract, uint256 _pid) external view override returns (uint256 balance) {
        (balance, ) = IEchidnaMasterChef(_stakingContract).userInfo(_pid, address(voter));
        return balance;
    }

    /**
     * @notice Claim and distribute rewards
     * @dev Restricted to strategy with _pid
     * @param _stakingContract Masterchef
     * @param _pid PID
     */
    function claimReward(address _stakingContract, uint256 _pid)
        external
        override
        onlyStrategy(_stakingContract, _pid)
    {
        voter.safeExecute(_stakingContract, 0, abi.encodeWithSignature("deposit(uint256,uint256)", _pid, 0));
        IVeEcdRewardPool(veEcdRewardPool).getReward(address(voter));
        _distributeReward();
    }

    /**
     * @notice Distribute rewards
     * @dev Restricted to strategy with _pid
     * @param _stakingContract Masterchef
     * @param _pid PID
     */
    function distributeReward(address _stakingContract, uint256 _pid)
        external
        override
        onlyStrategy(_stakingContract, _pid)
    {
        _distributeReward();
    }

    function _distributeReward() private {
        uint256 claimedECD = IERC20(ECD).balanceOf(address(voter));
        if (claimedECD > 0) {
            uint256 boostFee = _calculateBoostFee(claimedECD);
            uint256 reward = claimedECD.sub(boostFee);
            voter.safeExecute(ECD, 0, abi.encodeWithSignature("transfer(address,uint256)", msg.sender, reward));
            if (boostFee > 0) {
                voter.depositFromBalance(boostFee);
                IERC20(address(voter)).safeTransfer(boosterFeeReceiver, boostFee);
            }
        }
        uint256 claimedPTP = IERC20(PTP).balanceOf(address(voter));
        if (claimedPTP > 0) {
            voter.safeExecute(
                address(PTP),
                0,
                abi.encodeWithSignature("transfer(address,uint256)", msg.sender, claimedPTP)
            );
        }
    }

    function _calculateBoostFee(uint256 amount) private view returns (uint256 boostFee) {
        if (boosterFeeReceiver > address(0) && voter.depositsEnabled()) {
            boostFee = amount.mul(boosterFee).div(BIPS_DIVISOR);
        }
    }
}
