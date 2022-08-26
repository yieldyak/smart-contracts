// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../lib/SafeERC20.sol";
import "../../lib/SafeMath.sol";

import "./interfaces/IYetiVoter.sol";
import "./interfaces/IYetiVoterProxy.sol";
import "./interfaces/IYetiFarm.sol";

library SafeProxy {
    function safeExecute(
        IYetiVoter voter,
        address target,
        uint256 value,
        bytes memory data
    ) internal returns (bytes memory) {
        (bool success, bytes memory returnValue) = voter.execute(target, value, data);
        if (!success) revert("YetiVoterProxy::safeExecute failed");
        return returnValue;
    }
}

/**
 * @notice YetiVoterProxy is an upgradable contract.
 * Strategies interact with YetiVoterProxy and
 * YetiVoterProxy interacts with YetiVoter.
 * @dev For accounting reasons, there is one approved
 * strategy per staking contract. In case of upgrade,
 * use a new proxy.
 */
contract YetiVoterProxy is IYetiVoterProxy {
    using SafeMath for uint256;
    using SafeProxy for IYetiVoter;
    using SafeERC20 for IERC20;

    uint256 internal constant BIPS_DIVISOR = 10000;
    address private constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    IERC20 private constant YETI = IERC20(0x77777777777d4554c39223C354A05825b2E8Faa3);

    IYetiVoter public immutable voter;
    address public devAddr;
    uint256 public boosterFee;
    address public boosterFeeReceiver;

    // staking contract => strategy
    mapping(address => address) private approvedStrategies;

    modifier onlyDev() {
        require(msg.sender == devAddr, "YetiVoterProxy::onlyDev");
        _;
    }

    modifier onlyStrategy(address _stakingContract) {
        require(approvedStrategies[_stakingContract] == msg.sender, "YetiVoterProxy::onlyStrategy");
        _;
    }

    constructor(
        address _voter,
        address _devAddr,
        uint256 _boosterFeeBips,
        address _boosterFeeReceiver
    ) {
        devAddr = _devAddr;
        voter = IYetiVoter(_voter);
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
        require(approvedStrategies[_stakingContract] == address(0), "YetiVoterProxy::Strategy already added");
        approvedStrategies[_stakingContract] = _strategy;
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
     * @notice Move veYeti
     * @dev Restricted to devAddr
     * @param _from rewarder where to reduce
     * @param _to rewarder where to add
     * @param _amount to move
     */
    function moveVeYeti(
        address _from,
        address _to,
        uint256 _amount
    ) external onlyDev {
        IVeYeti.RewarderUpdate[] memory rewarderUpdates = new IVeYeti.RewarderUpdate[](2);
        rewarderUpdates[0] = IVeYeti.RewarderUpdate({rewarder: _from, amount: _amount, isIncrease: false});
        rewarderUpdates[1] = IVeYeti.RewarderUpdate({rewarder: _to, amount: _amount, isIncrease: true});
        voter.updateVeYeti(rewarderUpdates);
    }

    /**
     * @notice Deposit function
     * @dev Restricted to strategy with _pid
     * @param _stakingContract Masterchef
     * @param _token Deposit asset
     * @param _amount deposit amount
     */
    function deposit(
        address _stakingContract,
        address _token,
        uint256 _amount
    ) external override onlyStrategy(_stakingContract) {
        IERC20(_token).safeTransfer(address(voter), _amount);
        voter.safeExecute(_token, 0, abi.encodeWithSignature("approve(address,uint256)", _stakingContract, _amount));
        voter.safeExecute(_stakingContract, 0, abi.encodeWithSignature("deposit(uint256)", _amount));
        voter.safeExecute(_token, 0, abi.encodeWithSignature("approve(address,uint256)", _stakingContract, 0));
    }

    /**
     * @notice Withdraw function
     * @param _stakingContract Masterchef
     * @param _token Deposit asset
     * @param _amount withdraw amount
     */
    function withdraw(
        address _stakingContract,
        address _token,
        uint256 _amount
    ) external override onlyStrategy(_stakingContract) {
        voter.safeExecute(_stakingContract, 0, abi.encodeWithSignature("withdraw(uint256)", _amount));
        voter.safeExecute(_token, 0, abi.encodeWithSignature("transfer(address,uint256)", msg.sender, _amount));
    }

    /**
     * @notice Emergency withdraw function
     * @param _stakingContract Masterchef
     * @param _token Deposit asset
     */
    function emergencyWithdraw(address _stakingContract, address _token)
        external
        override
        onlyStrategy(_stakingContract)
    {
        uint256 balance = this.poolBalance(_stakingContract);
        voter.safeExecute(_stakingContract, 0, abi.encodeWithSignature("withdraw(uint256)", balance));
        voter.safeExecute(_token, 0, abi.encodeWithSignature("transfer(address,uint256)", msg.sender, balance));
    }

    /**
     * @notice Pending rewards matching interface for strategy
     * @param _stakingContract Masterchef
     */
    function pendingRewards(address _stakingContract) external view override returns (uint256 pendingYETI) {
        pendingYETI = IYetiFarm(_stakingContract).pendingTokens(address(voter));
        pendingYETI = pendingYETI.sub(_calculateBoostFee(pendingYETI));
    }

    /**
     * @notice Pool balance
     * @param _stakingContract Masterchef
     * @return balance in depositToken
     */
    function poolBalance(address _stakingContract) external view override returns (uint256 balance) {
        (balance, , ) = IYetiFarm(_stakingContract).userInfo(address(voter));
    }

    /**
     * @notice Claim and distribute rewards
     * @param _stakingContract Masterchef
     */
    function claimReward(address _stakingContract) external override onlyStrategy(_stakingContract) {
        voter.safeExecute(_stakingContract, 0, abi.encodeWithSignature("withdraw(uint256)", 0));
        uint256 claimedYETI = YETI.balanceOf(address(voter));
        if (claimedYETI > 0) {
            uint256 boostFee = _calculateBoostFee(claimedYETI);
            uint256 reward = claimedYETI.sub(boostFee);
            voter.safeExecute(
                address(YETI),
                0,
                abi.encodeWithSignature("transfer(address,uint256)", msg.sender, reward)
            );
            if (boostFee > 0) {
                IVeYeti.RewarderUpdate[] memory rewarderUpdates = new IVeYeti.RewarderUpdate[](1);
                rewarderUpdates[0] = IVeYeti.RewarderUpdate({
                    rewarder: _stakingContract,
                    amount: boostFee,
                    isIncrease: true
                });
                voter.depositFromBalance(boostFee, rewarderUpdates);
                IERC20(address(voter)).safeTransfer(boosterFeeReceiver, boostFee);
            }
        }
    }

    function _calculateBoostFee(uint256 amount) private view returns (uint256 boostFee) {
        if (boosterFeeReceiver > address(0) && voter.depositsEnabled()) {
            boostFee = amount.mul(boosterFee).div(BIPS_DIVISOR);
        }
    }
}
