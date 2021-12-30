// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

import "../lib/AccessControl.sol";
import "../lib/SafeMath.sol";

interface IERC20 {
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address owner) external view returns (uint);
}

interface IStrategy {
    function REINVEST_REWARD_BIPS() external view returns (uint);
    function ADMIN_FEE_BIPS() external view returns (uint);
    function DEV_FEE_BIPS() external view returns (uint);
    function transferOwnership(address newOwner) external;
    function updateMinTokensToReinvest(uint newValue) external;
    function updateAdminFee(uint newValue) external;
    function updateDevFee(uint newValue) external;
    function updateDepositsEnabled(bool newValue) external;
    function updateMaxTokensToDepositWithoutReinvest(uint newValue) external;
    function rescueDeployedFunds(uint minReturnAmountAccepted, bool disableDeposits) external;
    function updateReinvestReward(uint newValue) external;
    function recoverERC20(address tokenAddress, uint tokenAmount) external;
    function recoverAVAX(uint amount) external;
    function setAllowances() external;
    function revokeAllowance(address token, address spender) external;
    function allowDepositor(address depositor) external;
    function removeDepositor(address depositor) external;
}

interface IYakFeeCollector {
    function setDev(address strategy, address newDevAddr) external;
}

/**
 * @notice Role-based manager for YakStrategy contracts
 * @dev YakStrategyManager may be used as `owner` on YakStrategy contracts
 */
contract YakStrategyManagerV1 is AccessControl {
    using SafeMath for uint;

    uint public constant timelockLengthForOwnershipTransfer = 14 days;

    /// @notice Sets a global maximum for fee changes using bips (100 bips = 1%)
    uint public maxFeeBips = 1000;

    /// @notice Pending strategy owners (strategy => pending owner)
    mapping(address => address) public pendingOwners;

    /// @notice Earliest time pending owner can take effect (strategy => timestamp)
    mapping(address => uint) public pendingOwnersTimelock;

    /// @notice Role to manage strategy owners
    bytes32 public constant STRATEGY_OWNER_SETTER_ROLE = keccak256("STRATEGY_OWNER_SETTER_ROLE");

    /// @notice Role to initiate an emergency withdraw from strategies
    bytes32 public constant EMERGENCY_RESCUER_ROLE = keccak256("EMERGENCY_RESCUER_ROLE");

    /// @notice Role to sweep funds from strategies
    bytes32 public constant EMERGENCY_SWEEPER_ROLE = keccak256("EMERGENCY_SWEEPER_ROLE");

    /// @notice Role to manage global max fee configuration
    bytes32 public constant GLOBAL_MAX_FEE_SETTER_ROLE = keccak256("GLOBAL_MAX_FEE_SETTER_ROLE");

    /// @notice Role to manage strategy fees and reinvest configurations
    bytes32 public constant FEE_SETTER_ROLE = keccak256("FEE_SETTER_ROLE");

    /// @notice Role to allow/deny use of strategies
    bytes32 public constant STRATEGY_PERMISSIONER_ROLE = keccak256("STRATEGY_PERMISSIONER_ROLE");

    /// @notice Role to enable/disable deposits on strategies
    bytes32 public constant STRATEGY_DISABLER_ROLE = keccak256("STRATEGY_DISABLER_ROLE");

    /// @notice Role to allow/revoke token approvals on strategies
    bytes32 public constant TOKEN_APPROVER_ROLE = keccak256("TOKEN_APPROVER_ROLE");

    event ProposeOwner(address indexed strategy, address indexed newOwner);
    event SetOwner(address indexed strategy, address indexed newValue);
    event SetAdminFee(address indexed strategy, uint newValue);
    event SetDev(address indexed strategy, address newValue);
    event SetDevFee(address indexed strategy, uint newValue);
    event SetMinTokensToReinvest(address indexed strategy, uint newValue);
    event SetMaxTokensToDepositWithoutReinvest(address indexed strategy, uint newValue);
    event SetGlobalMaxFee(uint maxFeeBips, uint newMaxFeeBips);
    event SetReinvestReward(address indexed strategy, uint newValue);
    event SetDepositsEnabled(address indexed strategy, bool newValue);
    event SetAllowances(address indexed strategy);
    event Recover(address indexed strategy, address indexed token, uint amount);
    event EmergencyWithdraw(address indexed strategy);
    event AllowDepositor(address indexed strategy, address indexed depositor);
    event RemoveDepositor(address indexed strategy, address indexed depositor);

    constructor(
        address _manager,
        address _emergencyRescuer,
        address _emergencySweeper,
        address _globalFeeSetter,
        address _feeSetter,
        address _tokenApprover,
        address _strategyOwnerSetter,
        address _strategyDisabler,
        address _strategyPermissioner
    ) {
        _setupRole(DEFAULT_ADMIN_ROLE, _manager);
        _setupRole(EMERGENCY_RESCUER_ROLE, _emergencyRescuer);
        _setupRole(EMERGENCY_SWEEPER_ROLE, _emergencySweeper);
        _setupRole(STRATEGY_OWNER_SETTER_ROLE, _strategyOwnerSetter);
        _setupRole(GLOBAL_MAX_FEE_SETTER_ROLE, _globalFeeSetter);
        _setupRole(FEE_SETTER_ROLE, _feeSetter);
        _setupRole(TOKEN_APPROVER_ROLE, _tokenApprover);
        _setupRole(STRATEGY_PERMISSIONER_ROLE, _strategyPermissioner);
        _setupRole(STRATEGY_DISABLER_ROLE, _strategyDisabler);
    }

    receive() external payable {}

    /**
     * @notice Pass new value of `owner` through timelock
     * @dev Restricted to `STRATEGY_OWNER_SETTER_ROLE` to avoid griefing
     * @dev Resets timelock
     * @param strategy address
     * @param newOwner new value
     */
    function proposeOwner(address strategy, address newOwner) external {
        require(hasRole(STRATEGY_OWNER_SETTER_ROLE, msg.sender), "proposeOwner::auth");
        pendingOwnersTimelock[strategy] = block.timestamp + timelockLengthForOwnershipTransfer;
        pendingOwners[strategy] = newOwner;
        emit ProposeOwner(strategy, newOwner);
    }

    /**
     * @notice Set new value of `owner` and resets timelock
     * @dev This can be called by anyone
     * @param strategy address
     */
    function setOwner(address strategy) external {
        require(pendingOwnersTimelock[strategy] != 0, "setOwner::not allowed");
        require(pendingOwnersTimelock[strategy] <= block.timestamp, "setOwner::too soon");
        IStrategy(strategy).transferOwnership(pendingOwners[strategy]);
        emit SetOwner(strategy, pendingOwners[strategy]);
        delete pendingOwners[strategy];
        delete pendingOwnersTimelock[strategy];
    }

    /**
     * @notice Set new value of `devAddr`
     * @dev Restricted to `STRATEGY_OWNER_SETTER_ROLE`
     * @param yakFeeCollector existing dev
     * @param strategy address
     * @param newDevAddr new value
     */
    function setDev(address yakFeeCollector, address strategy, address newDevAddr) external {
        require(hasRole(STRATEGY_OWNER_SETTER_ROLE, msg.sender), "setDev::auth");
        IYakFeeCollector(yakFeeCollector).setDev(strategy, newDevAddr);
        emit SetDev(strategy, newDevAddr);
    }

    /**
     * @notice Set strategy fees
     * @dev Restricted to `feeSetter` and max fee
     * @param strategy address
     * @param devFeeBips platform fees
     * @param reinvestRewardBips reinvest reward
     */
    function setFees(address strategy, uint adminFeeBips, uint devFeeBips, uint reinvestRewardBips) external {
        require(hasRole(FEE_SETTER_ROLE, msg.sender), "setFees::auth");
        require(adminFeeBips.add(devFeeBips).add(reinvestRewardBips) <= maxFeeBips, "setFees::Fees too high");
        if (adminFeeBips != IStrategy(strategy).ADMIN_FEE_BIPS()){
            IStrategy(strategy).updateAdminFee(adminFeeBips);
            emit SetAdminFee(strategy, adminFeeBips);
        }
        if (devFeeBips != IStrategy(strategy).DEV_FEE_BIPS()){
            IStrategy(strategy).updateDevFee(devFeeBips);
            emit SetDevFee(strategy, devFeeBips);
        }
        if (reinvestRewardBips != IStrategy(strategy).REINVEST_REWARD_BIPS()){
            IStrategy(strategy).updateReinvestReward(reinvestRewardBips);
            emit SetReinvestReward(strategy, reinvestRewardBips);
        }
    }

    /**
     * @notice Sets token approvals
     * @dev Restricted to `TOKEN_APPROVER_ROLE` to avoid griefing
     * @param strategy address
     */
    function setAllowances(address strategy) external {
        require(hasRole(TOKEN_APPROVER_ROLE, msg.sender), "setFees::auth");
        IStrategy(strategy).setAllowances();
        emit SetAllowances(strategy);
    }

    /**
     * @notice Revokes token approvals
     * @dev Restricted to `TOKEN_APPROVER_ROLE` to avoid griefing
     * @param strategy address
     * @param token address
     * @param spender address
     */
    function revokeAllowance(address strategy, address token, address spender) external {
        require(hasRole(TOKEN_APPROVER_ROLE, msg.sender), "setFees::auth");
        IStrategy(strategy).revokeAllowance(token, spender);
    }

    /**
     * @notice Set max strategy fees
     * @dev Restricted to `GLOBAL_MAX_FEE_SETTER_ROLE`
     * @param newMaxFeeBips max strategy fees
     */
    function updateGlobalMaxFees(uint newMaxFeeBips) external {
        require(hasRole(GLOBAL_MAX_FEE_SETTER_ROLE, msg.sender), "updateGlobalMaxFees::auth");
        emit SetGlobalMaxFee(maxFeeBips, newMaxFeeBips);
        maxFeeBips = newMaxFeeBips;
    }

    /**
     * @notice Set min tokens to reinvest
     * @dev Restricted to `FEE_SETTER_ROLE`
     * @param strategy address
     * @param newValue min tokens to reinvest
     */
    function setMinTokensToReinvest(address strategy, uint newValue) external {
        require(hasRole(FEE_SETTER_ROLE, msg.sender), "setFees::auth");
        IStrategy(strategy).updateMinTokensToReinvest(newValue);
        emit SetMinTokensToReinvest(strategy, newValue);
    }

    /**
     * @notice Permissioned function to set max tokens to deposit without reinvest
     * @dev Restricted to `FEE_SETTER_ROLE`
     * @param strategy address
     * @param newValue max tokens to deposit without reinvest
     */
    function setMaxTokensToDepositWithoutReinvest(address strategy, uint newValue) external {
        require(hasRole(FEE_SETTER_ROLE, msg.sender), "setMaxTokensToDepositWithoutReinvest::auth");
        IStrategy(strategy).updateMaxTokensToDepositWithoutReinvest(newValue);
        emit SetMaxTokensToDepositWithoutReinvest(strategy, newValue);
    }

    /**
     * @notice Enable/disable deposits
     * @dev Restricted to `STRATEGY_DISABLER_ROLE`
     * @param strategy address
     * @param newValue bool
     */
    function setDepositsEnabled(address strategy, bool newValue) external {
        require(hasRole(STRATEGY_DISABLER_ROLE, msg.sender), "setDepositsEnabled::auth");
        IStrategy(strategy).updateDepositsEnabled(newValue);
        emit SetDepositsEnabled(strategy, newValue);
    }

    /**
     * @notice Add to list of allowed depositors
     * @dev Restricted to `STRATEGY_PERMISSIONER_ROLE`
     * @param strategy address
     * @param depositor address
     */
    function allowDepositor(address strategy, address depositor) external {
        require(hasRole(STRATEGY_PERMISSIONER_ROLE, msg.sender), "allowDepositor::auth");
        IStrategy(strategy).allowDepositor(depositor);
        emit AllowDepositor(strategy, depositor);
    }

    /**
     * @notice Remove from list of allowed depositors
     * @dev Restricted to `STRATEGY_PERMISSIONER_ROLE`
     * @param strategy address
     * @param depositor address
     */
    function removeDepositor(address strategy, address depositor) external {
        require(hasRole(STRATEGY_PERMISSIONER_ROLE, msg.sender), "removeDepositor::auth");
        IStrategy(strategy).removeDepositor(depositor);
        emit RemoveDepositor(strategy, depositor);
    }

    /**
     * @notice Immediately pull deployed assets back into the strategy contract
     * @dev Restricted to `EMERGENCY_RESCUER_ROLE`
     * @dev Rescued funds stay in strategy until recovered (see `recoverTokens`)
     * @param strategy address
     * @param minReturnAmountAccepted amount
     * @param disableDeposits bool
     */
    function rescueDeployedFunds(address strategy, uint minReturnAmountAccepted, bool disableDeposits) external {
        require(hasRole(EMERGENCY_RESCUER_ROLE, msg.sender), "rescueDeployedFunds::auth");
        IStrategy(strategy).rescueDeployedFunds(minReturnAmountAccepted, disableDeposits);
        emit EmergencyWithdraw(strategy);
    }

    /**
     * @notice Recover any token, including deposit tokens from strategy
     * @dev Restricted to `EMERGENCY_SWEEPER_ROLE`
     * @dev Intended for use in case of `rescueDeployedFunds`, as deposit tokens will be locked in the strategy.
     * @param strategy address
     * @param tokenAddress address
     * @param tokenAmount amount
     */
    function recoverTokens(address strategy, address tokenAddress, uint tokenAmount) external {
        require(hasRole(EMERGENCY_SWEEPER_ROLE, msg.sender), "recoverTokens::auth");
        IStrategy(strategy).recoverERC20(tokenAddress, tokenAmount);
        uint balance = IERC20(tokenAddress).balanceOf(address(this));
        if (tokenAmount < balance) {
            tokenAmount = balance;
        }
        require(IERC20(tokenAddress).transfer(msg.sender, tokenAmount), "recoverDepositTokens::transfer failed");
        emit Recover(strategy, tokenAddress, tokenAmount);
    }

    /**
     * @notice Recover AVAX from strategy
     * @dev Restricted to `EMERGENCY_SWEEPER_ROLE`
     * @dev After recovery, use `sweepAVAX`. Contract becomes gas-bound.
     * @dev Intended for use in case of `rescueDeployedFunds`, as deposit tokens will be locked in the strategy.
     * @param strategy address
     * @param amount amount
     */
    function recoverAVAX(address strategy, uint amount) external {
        require(hasRole(EMERGENCY_SWEEPER_ROLE, msg.sender), "recoverAVAX::auth");
        IStrategy(strategy).recoverAVAX(amount);
        emit Recover(strategy, address(0), amount);
    }

    /**
     * @notice Sweep AVAX from contract
     * @dev Restricted to `EMERGENCY_SWEEPER_ROLE`
     * @param amount amount
     */
    function sweepAVAX(uint amount) external {
        require(hasRole(EMERGENCY_SWEEPER_ROLE, msg.sender), "sweepAVAX::auth");
        uint balance = address(this).balance;
        if (amount < balance) {
            amount = balance;
        }
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success == true, "recoverAVAX::transfer failed");
    }
}