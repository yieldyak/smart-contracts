// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;
pragma experimental ABIEncoderV2;

import "../interfaces/IJoeVoter.sol";
import "../interfaces/IJoeVoterProxy.sol";
import "../interfaces/IJoeChef.sol";
import "../interfaces/IBoostedJoeStrategyForLP.sol";
import "../interfaces/IVeJoeStaking.sol";
import "../lib/SafeERC20.sol";

library SafeProxy {
    function safeExecute(
        IJoeVoter voter,
        address target,
        uint256 value,
        bytes memory data
    ) internal returns (bytes memory) {
        (bool success, bytes memory returnValue) = voter.execute(target, value, data);
        if (!success) revert("JoeVoterProxy::safeExecute failed");
        return returnValue;
    }
}

/**
 * @notice JoeVoterProxy is an upgradable contract.
 * Strategies interact with JoeVoterProxy and
 * JoeVoterProxy interacts with JoeVoter.
 * @dev For accounting reasons, there is one approved
 * strategy per Masterchef PID. In case of upgrade,
 * use a new proxy.
 */
contract JoeVoterProxy is IJoeVoterProxy {
    using SafeMath for uint256;
    using SafeProxy for IJoeVoter;
    using SafeERC20 for IERC20;

    struct FeeSettings {
        uint256 stakerFeeBips;
        uint256 boosterFeeBips;
        address stakerFeeReceiver;
        address boosterFeeReceiver;
    }

    uint256 internal constant BIPS_DIVISOR = 10000;

    uint256 public boosterFee;
    uint256 public stakerFee;
    address public stakerFeeReceiver;
    address public boosterFeeReceiver;
    address private constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    address public constant JOE = 0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd;
    address public constant veJoeStaking = 0x25D85E17dD9e544F6E9F8D44F99602dbF5a97341;
    IJoeVoter public immutable voter;
    address public devAddr;

    // staking contract => pid => strategy
    mapping(address => mapping(uint256 => address)) private approvedStrategies;

    modifier onlyDev() {
        require(msg.sender == devAddr, "JoeVoterProxy::onlyDev");
        _;
    }

    modifier onlyStrategy(address _stakingContract, uint256 _pid) {
        require(approvedStrategies[_stakingContract][_pid] == msg.sender, "JoeVoterProxy::onlyStrategy");
        _;
    }

    constructor(
        address _voter,
        address _devAddr,
        FeeSettings memory _feeSettings
    ) {
        devAddr = _devAddr;
        boosterFee = _feeSettings.boosterFeeBips;
        stakerFee = _feeSettings.stakerFeeBips;
        stakerFeeReceiver = _feeSettings.stakerFeeReceiver;
        boosterFeeReceiver = _feeSettings.boosterFeeReceiver;
        voter = IJoeVoter(_voter);
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
        uint256 pid = IBoostedJoeStrategyForLP(_strategy).PID();
        require(
            approvedStrategies[_stakingContract][pid] == address(0),
            "JoeVoterProxy::Strategy for PID already added"
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
     * @notice Update staker fee
     * @dev Restricted to devAddr
     * @param _stakerFeeBips new fee in bips (1% = 100 bips)
     */
    function setStakerFee(uint256 _stakerFeeBips) external onlyDev {
        stakerFee = _stakerFeeBips;
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
     * @notice Update staker fee receiver
     * @dev Restricted to devAddr
     * @param _stakerFeeReceiver address
     */
    function setStakerFeeReceiver(address _stakerFeeReceiver) external onlyDev {
        stakerFeeReceiver = _stakerFeeReceiver;
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
     * @notice Calculation of reinvest fee (boost + staking)
     * @return reinvest fee
     */
    function reinvestFeeBips() external view override returns (uint256) {
        uint256 boostFee = 0;
        if (boosterFee > 0 && boosterFeeReceiver > address(0) && voter.depositsEnabled()) {
            boostFee = boosterFee;
        }

        uint256 stakingFee = 0;
        if (stakerFee > 0 && stakerFeeReceiver > address(0)) {
            stakingFee = stakerFee;
        }
        return boostFee.add(stakingFee);
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
     * @return pendingJoe
     * @return bonusTokenAddress
     * @return pendingBonusToken
     */
    function pendingRewards(address _stakingContract, uint256 _pid)
        external
        view
        override
        returns (
            uint256 pendingJoe,
            address bonusTokenAddress,
            uint256 pendingBonusToken
        )
    {
        (pendingJoe, bonusTokenAddress, , pendingBonusToken) = IJoeChef(_stakingContract).pendingTokens(
            _pid,
            address(voter)
        );
        uint256 reinvestFee = pendingJoe.mul(this.reinvestFeeBips()).div(BIPS_DIVISOR);

        return (pendingJoe.sub(reinvestFee), bonusTokenAddress, pendingBonusToken);
    }

    function poolBalance(address _stakingContract, uint256 _pid) external view override returns (uint256 balance) {
        return _poolBalance(_stakingContract, _pid);
    }

    /**
     * @notice Pool balance
     * @param _stakingContract Masterchef
     * @param _pid PID
     * @return balance in depositToken
     */
    function _poolBalance(address _stakingContract, uint256 _pid) internal view returns (uint256 balance) {
        (balance, ) = IJoeChef(_stakingContract).userInfo(_pid, address(voter));
    }

    /**
     * @notice Claim and distribute rewards
     * @dev Restricted to strategy with _pid
     * @param _stakingContract Masterchef
     * @param _pid PID
     */
    function claimReward(
        uint256 _pid,
        address _stakingContract,
        address _extraToken
    ) external override onlyStrategy(_stakingContract, _pid) {
        voter.safeExecute(_stakingContract, 0, abi.encodeWithSignature("deposit(uint256,uint256)", _pid, 0));
        _distributeReward(_extraToken);
    }

    /**
     * @notice Distribute rewards
     * @dev Restricted to strategy with _pid
     * @param _stakingContract Masterchef
     * @param _pid PID
     */
    function distributeReward(
        uint256 _pid,
        address _stakingContract,
        address _extraToken
    ) external override onlyStrategy(_stakingContract, _pid) {
        _distributeReward(_extraToken);
    }

    function _distributeReward(address _extraToken) private {
        if (_extraToken == WAVAX) {
            voter.wrapAvaxBalance();
        }

        uint256 pendingJoe = IERC20(JOE).balanceOf(address(voter));
        uint256 pendingExtraToken = _extraToken > address(0) ? IERC20(_extraToken).balanceOf(address(voter)) : 0;
        if (pendingJoe > 0) {
            uint256 boostFee = 0;
            if (boosterFee > 0 && boosterFeeReceiver > address(0) && voter.depositsEnabled()) {
                boostFee = pendingJoe.mul(boosterFee).div(BIPS_DIVISOR);
                voter.depositFromBalance(boostFee);
                IERC20(address(voter)).safeTransfer(boosterFeeReceiver, boostFee);
            }

            uint256 stakingFee = 0;
            if (stakerFee > 0 && stakerFeeReceiver > address(0)) {
                stakingFee = pendingJoe.mul(stakerFee).div(BIPS_DIVISOR);
                voter.safeExecute(
                    JOE,
                    0,
                    abi.encodeWithSignature("transfer(address,uint256)", stakerFeeReceiver, stakingFee)
                );
            }

            uint256 reward = pendingJoe.sub(boostFee).sub(stakingFee);
            voter.safeExecute(JOE, 0, abi.encodeWithSignature("transfer(address,uint256)", msg.sender, reward));
        }

        if (pendingExtraToken > 0) {
            voter.safeExecute(
                _extraToken,
                0,
                abi.encodeWithSignature("transfer(address,uint256)", msg.sender, pendingExtraToken)
            );
        }

        if (IVeJoeStaking(veJoeStaking).getPendingVeJoe(address(voter)) > 0) {
            voter.claimVeJOE();
        }
    }
}
