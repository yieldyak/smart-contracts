// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface IERC20 {
    function transfer(address recipient, uint256 amount) external returns (bool);
}

interface IStrategy {
    function owner() external view returns (address);

    function renounceOwnership() external;

    function transferOwnership(address newOwner) external;

    function emergencyWithdraw() external;

    function updateMinTokensToReinvest(uint256 newValue) external;

    function updateAdminFee(uint256 newValue) external;

    function updateDevFee(uint256 newValue) external;

    function updateDepositsEnabled(bool newValue) external;

    function updateMaxTokensToDepositWithoutReinvest(uint256 newValue) external;

    function rescueDeployedFunds(uint256 minReturnAmountAccepted, bool disableDeposits) external;

    function updateReinvestReward(uint256 newValue) external;

    function recoverERC20(address tokenAddress, uint256 tokenAmount) external;

    function recoverAVAX(uint256 amount) external;

    function setAllowances() external;

    function allowDepositor(address depositor) external;

    function removeDepositor(address depositor) external;
}

/**
 * @notice A generic timelock for YakStrategies
 * @dev Ensure function is supported by strategy
 */
contract YakTimelockForDexStrategyV4 {
    uint256 public constant timelockLengthForAssetRecovery = 2 days;
    uint256 public constant timelockLengthForOwnershipTransfer = 4 days;
    uint256 public constant timelockLengthForFeeChanges = 8 hours;
    address public immutable manager;
    address public immutable feeCollector;

    mapping(address => address) public pendingOwners;
    mapping(address => uint256) public pendingAdminFees;
    mapping(address => uint256) public pendingDevFees;
    mapping(address => uint256) public pendingReinvestRewards;
    mapping(address => address) public pendingTokenAddressesToRecover;
    mapping(address => uint256) public pendingTokenAmountsToRecover;
    mapping(address => uint256) public pendingAVAXToRecover;
    mapping(PermissionedTimelockFunctions => address[]) public permissionedFunctionOwners;

    event grant(PermissionedTimelockFunctions _ptf, address indexed account);
    event revoke(PermissionedTimelockFunctions _ptf, address indexed account);
    event ProposeOwner(address indexed strategy, address indexed proposedValue, uint256 timelock);
    event ProposeAdminFee(address indexed strategy, uint256 proposedValue, uint256 timelock);
    event ProposeDevFee(address indexed strategy, uint256 proposedValue, uint256 timelock);
    event ProposeReinvestReward(address indexed strategy, uint256 proposedValue, uint256 timelock);
    event ProposeRecovery(
        address indexed strategy,
        address indexed proposedToken,
        uint256 proposedValue,
        uint256 timelock
    );

    event SetOwner(address indexed strategy, address indexed newValue);
    event SetAdminFee(address indexed strategy, uint256 newValue);
    event SetDevFee(address indexed strategy, uint256 newValue);
    event SetReinvestReward(address indexed strategy, uint256 newValue);
    event SetMinTokensToReinvest(address indexed strategy, uint256 newValue);
    event SetDepositsEnabled(address indexed strategy, bool newValue);
    event Sweep(address indexed token, uint256 amount);
    event Recover(address indexed strategy, address indexed token, uint256 amount);
    event EmergencyWithdraw(address indexed strategy);
    event SetAllowances(address indexed strategy);
    event SetMaxTokensToDepositWithoutReinvest(address indexed strategy, uint256 newValue);
    event AllowDepositor(address indexed strategy, address indexed depositor);
    event RemoveDepositor(address indexed strategy, address indexed depositor);

    enum Functions {
        renounceOwnership,
        transferOwnership,
        emergencyWithdraw,
        updateMinTokensToReinvest,
        updateAdminFee,
        updateDevFee,
        updateReinvestReward,
        recoverERC20,
        recoverAVAX
    }

    enum PermissionedTimelockFunctions {
        sweepTokens,
        sweepAVAX,
        proposeOwner,
        proposeAdminFee,
        proposeDevFee,
        proposeReinvestReward,
        proposeRecoverERC20,
        proposeRecoverAVAX,
        setMinTokensToReinvest,
        setMaxTokensToDepositWithoutReinvest,
        setDepositsEnabled,
        emergencyWithdraw,
        rescueDeployedFunds,
        setAllowances,
        allowDepositor,
        removeDepositor
    }

    mapping(PermissionedTimelockFunctions => mapping(address => bool)) public authorizedAddressess;
    mapping(address => mapping(Functions => uint256)) public timelock;

    constructor() {
        manager = msg.sender;
        feeCollector = msg.sender;
    }

    // Modifiers

    /**
     * @notice Restrict to `emergencyWithdraw`
     * @dev To change, call revokeRole with emergencyWithdraw_ADMIN
     */
    modifier hasPermission(PermissionedTimelockFunctions _ptf, address account) {
        require((authorizedAddressess[_ptf][account]) || msg.sender == manager, "Caller doesnt have permission");
        _;
    }

    /**
     * @notice Restrict to `manager`
     * @dev To change manager, deploy new timelock and transfer strategy ownership
     */
    modifier onlyManager() {
        require(msg.sender == manager);
        _;
    }

    /**
     * @notice Restrict to `feeCollector`
     * @dev To change feeCollector, deploy new timelock and transfer strategy ownership
     */
    modifier onlyFeeCollector() {
        require(msg.sender == feeCollector);
        _;
    }

    /**
     * @notice Set timelock when changing pending values
     * @param _strategy address
     * @param _fn Function enum value
     * @param timelockLength in seconds
     */
    modifier setTimelock(
        address _strategy,
        Functions _fn,
        uint256 timelockLength
    ) {
        timelock[_strategy][_fn] = block.timestamp + timelockLength;
        _;
    }

    /**
     * @notice Enforce timelock for a given function
     * @dev Ends execution by resetting timelock to avoid replay
     * @param _strategy address
     * @param _fn Function enum value
     */
    modifier enforceTimelock(address _strategy, Functions _fn) {
        require(
            timelock[_strategy][_fn] != 0 && timelock[_strategy][_fn] <= block.timestamp,
            "YakTimelockManager::enforceTimelock"
        );
        _;
        timelock[_strategy][_fn] = 0;
    }

    /**
     * @notice Grant access for a time lock method for an account
     * @param _ptf PermissionedTimelockFunctions enum value for the desired method
     * @param account address to grant the access
     */
    function grantAccountAccess(PermissionedTimelockFunctions _ptf, address account) external onlyManager {
        require(!authorizedAddressess[_ptf][account], "Account has already been given access");
        emit grant(_ptf, account);
        authorizedAddressess[_ptf][account] = true;
        permissionedFunctionOwners[_ptf].push(account);
    }

    /**
     * @notice Revokes access for a time lock method for an account
     * @param _ptf PermissionedTimelockFunctions enum value for the desired method
     * @param account address to revoke the access
     */
    function revokeAccountAccess(PermissionedTimelockFunctions _ptf, address account) external onlyManager {
        require(authorizedAddressess[_ptf][account], "Account has no access");
        emit revoke(_ptf, account);
        uint256 accountIndex = permissionedFunctionOwners[_ptf].length + 1;
        for (uint256 i = 0; i < permissionedFunctionOwners[_ptf].length; i++) {
            if (permissionedFunctionOwners[_ptf][i] == account) {
                accountIndex = i;
                break;
            }
        }
        require(accountIndex < permissionedFunctionOwners[_ptf].length, "Account not found");
        authorizedAddressess[_ptf][account] = false;
        _removeElement(_ptf, accountIndex);
    }

    /**
     * @notice returns a list of addressess that have grant access to a timelock function
     * @dev The timelock contract may receive assets from both revenue and asset recovery.
     * @dev The sweep function is NOT timelocked, because recovered assets must go through separate timelock functions.
     * @param _ptf PermissionedTimelockFunctions enum value for the desired method
     */
    function listofGrantedAccounts(PermissionedTimelockFunctions _ptf)
        external
        view
        onlyManager
        returns (address[] memory)
    {
        return permissionedFunctionOwners[_ptf];
    }

    /**
     * @notice Sweep tokens from the timelock to `feeCollector`
     * @dev The timelock contract may receive assets from both revenue and asset recovery.
     * @dev The sweep function is NOT timelocked, because recovered assets must go through separate timelock functions.
     * @param tokenAddress address
     * @param tokenAmount amount
     */
    function sweepTokens(address tokenAddress, uint256 tokenAmount)
        external
        hasPermission(PermissionedTimelockFunctions.sweepTokens, msg.sender)
    {
        require(tokenAmount > 0, "YakTimelockManager::sweepTokens, amount too low");
        require(
            IERC20(tokenAddress).transfer(msg.sender, tokenAmount),
            "YakTimelockManager::sweepTokens, transfer failed"
        );
        emit Sweep(tokenAddress, tokenAmount);
    }

    /**
     * @notice Sweep AVAX from the timelock to the `feeCollector` address
     * @dev The timelock contract may receive assets from both revenue and asset recovery.
     * @dev The sweep function is NOT timelocked, because recovered assets must go through separate timelock functions.
     * @param amount amount
     */
    function sweepAVAX(uint256 amount) external hasPermission(PermissionedTimelockFunctions.sweepAVAX, msg.sender) {
        require(amount > 0, "YakTimelockManager::sweepAVAX, amount too low");
        msg.sender.transfer(amount);
        emit Sweep(address(0), amount);
    }

    // Functions with timelocks

    /**
     * @notice Pass new value of `owner` through timelock
     * @dev Restricted to `manager` to avoid griefing
     * @dev Resets timelock duration through modifier
     * @param _strategy address
     * @param _pendingOwner new value
     */
    function proposeOwner(address _strategy, address _pendingOwner)
        external
        onlyManager
        setTimelock(_strategy, Functions.transferOwnership, timelockLengthForOwnershipTransfer)
    {
        pendingOwners[_strategy] = _pendingOwner;
        emit ProposeOwner(_strategy, _pendingOwner, timelock[_strategy][Functions.transferOwnership]);
    }

    /**
     * @notice Set new value of `owner` and resets timelock
     * @dev This can be called by anyone
     * @param _strategy address
     */
    function setOwner(address _strategy) external enforceTimelock(_strategy, Functions.transferOwnership) {
        IStrategy(_strategy).transferOwnership(pendingOwners[_strategy]);
        emit SetOwner(_strategy, pendingOwners[_strategy]);
        pendingOwners[_strategy] = address(0);
    }

    /**
     * @notice Pass new value of `adminFee` through timelock
     * @dev Restricted to `manager` to avoid griefing
     * @dev Resets timelock duration through modifier
     * @param _strategy address
     * @param _pendingAdminFee new value
     */
    function proposeAdminFee(address _strategy, uint256 _pendingAdminFee)
        external
        hasPermission(PermissionedTimelockFunctions.proposeAdminFee, msg.sender)
        setTimelock(_strategy, Functions.updateAdminFee, timelockLengthForFeeChanges)
    {
        pendingAdminFees[_strategy] = _pendingAdminFee;
        emit ProposeAdminFee(_strategy, _pendingAdminFee, timelock[_strategy][Functions.updateAdminFee]);
    }

    /**
     * @notice Set new value of `adminFee` and reset timelock
     * @dev This can be called by anyone
     * @param _strategy address
     */
    function setAdminFee(address _strategy) external enforceTimelock(_strategy, Functions.updateAdminFee) {
        IStrategy(_strategy).updateAdminFee(pendingAdminFees[_strategy]);
        emit SetAdminFee(_strategy, pendingAdminFees[_strategy]);
        pendingAdminFees[_strategy] = 0;
    }

    /**
     * @notice Pass new value of `devFee` through timelock
     * @dev Restricted to `manager` to avoid griefing
     * @dev Resets timelock duration through modifier
     * @param _strategy address
     * @param _pendingDevFee new value
     */
    function proposeDevFee(address _strategy, uint256 _pendingDevFee)
        external
        hasPermission(PermissionedTimelockFunctions.proposeDevFee, msg.sender)
        setTimelock(_strategy, Functions.updateDevFee, timelockLengthForFeeChanges)
    {
        pendingDevFees[_strategy] = _pendingDevFee;
        emit ProposeDevFee(_strategy, _pendingDevFee, timelock[_strategy][Functions.updateDevFee]);
    }

    /**
     * @notice Set new value of `devFee` and reset timelock
     * @dev This can be called by anyone
     * @param _strategy address
     */
    function setDevFee(address _strategy) external enforceTimelock(_strategy, Functions.updateDevFee) {
        IStrategy(_strategy).updateDevFee(pendingDevFees[_strategy]);
        emit SetDevFee(_strategy, pendingDevFees[_strategy]);
        pendingDevFees[_strategy] = 0;
    }

    /**
     * @notice Pass new value of `reinvestReward` through timelock
     * @dev Restricted to `manager` to avoid griefing
     * @dev Resets timelock duration through modifier
     * @param _strategy address
     * @param _pendingReinvestReward new value
     */
    function proposeReinvestReward(address _strategy, uint256 _pendingReinvestReward)
        external
        hasPermission(PermissionedTimelockFunctions.proposeReinvestReward, msg.sender)
        setTimelock(_strategy, Functions.updateReinvestReward, timelockLengthForFeeChanges)
    {
        pendingReinvestRewards[_strategy] = _pendingReinvestReward;
        emit ProposeReinvestReward(
            _strategy,
            _pendingReinvestReward,
            timelock[_strategy][Functions.updateReinvestReward]
        );
    }

    /**
     * @notice Set new value of `reinvestReward` and reset timelock
     * @dev This can be called by anyone
     * @param _strategy address
     */
    function setReinvestReward(address _strategy) external enforceTimelock(_strategy, Functions.updateReinvestReward) {
        IStrategy(_strategy).updateReinvestReward(pendingReinvestRewards[_strategy]);
        emit SetReinvestReward(_strategy, pendingReinvestRewards[_strategy]);
        pendingReinvestRewards[_strategy] = 0;
    }

    /**
     * @notice Pass values for `recoverERC20` through timelock
     * @dev Restricted to `manager` to avoid griefing
     * @dev Resets timelock duration through modifier
     * @param _strategy address
     * @param _pendingTokenAddressToRecover address
     * @param _pendingTokenAmountToRecover amount
     */
    function proposeRecoverERC20(
        address _strategy,
        address _pendingTokenAddressToRecover,
        uint256 _pendingTokenAmountToRecover
    )
        external
        hasPermission(PermissionedTimelockFunctions.proposeRecoverERC20, msg.sender)
        setTimelock(_strategy, Functions.recoverERC20, timelockLengthForAssetRecovery)
    {
        pendingTokenAddressesToRecover[_strategy] = _pendingTokenAddressToRecover;
        pendingTokenAmountsToRecover[_strategy] = _pendingTokenAmountToRecover;
        emit ProposeRecovery(
            _strategy,
            _pendingTokenAddressToRecover,
            _pendingTokenAmountToRecover,
            timelock[_strategy][Functions.recoverERC20]
        );
    }

    /**
     * @notice Call `recoverERC20` and reset timelock
     * @dev This can be called by anyone
     * @dev Recoverd funds are collected to this timelock and may be swept
     * @param _strategy address
     */
    function setRecoverERC20(address _strategy) external enforceTimelock(_strategy, Functions.recoverERC20) {
        IStrategy(_strategy).recoverERC20(
            pendingTokenAddressesToRecover[_strategy],
            pendingTokenAmountsToRecover[_strategy]
        );
        emit Recover(_strategy, pendingTokenAddressesToRecover[_strategy], pendingTokenAmountsToRecover[_strategy]);
        pendingTokenAddressesToRecover[_strategy] = address(0);
        pendingTokenAmountsToRecover[_strategy] = 0;
    }

    /**
     * @notice Pass values for `recoverAVAX` through timelock
     * @dev Restricted to `manager` to avoid griefing
     * @dev Resets timelock duration through modifier
     * @param _strategy address
     * @param _pendingAVAXToRecover amount
     */
    function proposeRecoverAVAX(address _strategy, uint256 _pendingAVAXToRecover)
        external
        hasPermission(PermissionedTimelockFunctions.proposeRecoverAVAX, msg.sender)
        setTimelock(_strategy, Functions.recoverAVAX, timelockLengthForAssetRecovery)
    {
        pendingAVAXToRecover[_strategy] = _pendingAVAXToRecover;
        emit ProposeRecovery(_strategy, address(0), _pendingAVAXToRecover, timelock[_strategy][Functions.recoverAVAX]);
    }

    /**
     * @notice Call `recoverAVAX` and reset timelock
     * @dev This can be called by anyone
     * @dev Recoverd funds are collected to this timelock and may be swept
     * @param _strategy address
     */
    function setRecoverAVAX(address _strategy) external enforceTimelock(_strategy, Functions.recoverAVAX) {
        IStrategy(_strategy).recoverAVAX(pendingAVAXToRecover[_strategy]);
        emit Recover(_strategy, address(0), pendingAVAXToRecover[_strategy]);
        pendingAVAXToRecover[_strategy] = 0;
    }

    // Functions without timelocks

    /**
     * @notice Set new value of `minTokensToReinvest`
     * @dev Restricted to `manager` to avoid griefing
     * @param _strategy address
     * @param newValue min tokens
     */
    function setMinTokensToReinvest(address _strategy, uint256 newValue)
        external
        hasPermission(PermissionedTimelockFunctions.setMinTokensToReinvest, msg.sender)
    {
        IStrategy(_strategy).updateMinTokensToReinvest(newValue);
        emit SetMinTokensToReinvest(_strategy, newValue);
    }

    /**
     * @notice Set new value of `maxTokensToDepositWithoutReinvest`
     * @dev Restricted to `manager` to avoid griefing
     * @param _strategy address
     * @param newValue max tokens
     */
    function setMaxTokensToDepositWithoutReinvest(address _strategy, uint256 newValue)
        external
        hasPermission(PermissionedTimelockFunctions.setMaxTokensToDepositWithoutReinvest, msg.sender)
    {
        IStrategy(_strategy).updateMaxTokensToDepositWithoutReinvest(newValue);
        emit SetMaxTokensToDepositWithoutReinvest(_strategy, newValue);
    }

    /**
     * @notice Enable/disable deposits (After YakStrategy)
     * @param _strategy address
     * @param newValue bool
     */
    function setDepositsEnabled(address _strategy, bool newValue)
        external
        hasPermission(PermissionedTimelockFunctions.setDepositsEnabled, msg.sender)
    {
        IStrategy(_strategy).updateDepositsEnabled(newValue);
        emit SetDepositsEnabled(_strategy, newValue);
    }

    /**
     * @notice Rescues deployed assets to the strategy contract (Before YakStrategy)
     * @dev Restricted to `manager` to avoid griefing
     * @param _strategy address
     */
    function emergencyWithdraw(address _strategy)
        external
        hasPermission(PermissionedTimelockFunctions.emergencyWithdraw, msg.sender)
    {
        IStrategy(_strategy).emergencyWithdraw();
        emit EmergencyWithdraw(_strategy);
    }

    /**
     * @notice Rescues deployed assets to the strategy contract (After YakStrategy)
     * @dev Restricted to `manager` to avoid griefing
     * @param _strategy address
     * @param minReturnAmountAccepted amount
     * @param disableDeposits bool
     */
    function rescueDeployedFunds(
        address _strategy,
        uint256 minReturnAmountAccepted,
        bool disableDeposits
    ) external hasPermission(PermissionedTimelockFunctions.rescueDeployedFunds, msg.sender) {
        IStrategy(_strategy).rescueDeployedFunds(minReturnAmountAccepted, disableDeposits);
        emit EmergencyWithdraw(_strategy);
    }

    /**
     * @notice Sets token approvals
     * @dev Restricted to `manager` to avoid griefing
     * @param _strategy address
     */
    function setAllowances(address _strategy)
        external
        hasPermission(PermissionedTimelockFunctions.setAllowances, msg.sender)
    {
        IStrategy(_strategy).setAllowances();
        emit SetAllowances(_strategy);
    }

    /**
     * @notice Add to list of allowed depositors
     * @param _strategy address
     * @param depositor address
     */
    function allowDepositor(address _strategy, address depositor)
        external
        hasPermission(PermissionedTimelockFunctions.allowDepositor, msg.sender)
    {
        IStrategy(_strategy).allowDepositor(depositor);
        emit AllowDepositor(_strategy, depositor);
    }

    /**
     * @notice Remove from list of allowed depositors
     * @param _strategy address
     * @param depositor address
     */
    function removeDepositor(address _strategy, address depositor)
        external
        hasPermission(PermissionedTimelockFunctions.removeDepositor, msg.sender)
    {
        IStrategy(_strategy).removeDepositor(depositor);
        emit RemoveDepositor(_strategy, depositor);
    }

    function _removeElement(PermissionedTimelockFunctions _ptf, uint256 index) internal {
        if (index >= permissionedFunctionOwners[_ptf].length) return;
        for (uint256 i = index; i < permissionedFunctionOwners[_ptf].length - 1; i++) {
            permissionedFunctionOwners[_ptf][i] = permissionedFunctionOwners[_ptf][i + 1];
        }
        permissionedFunctionOwners[_ptf].pop();
    }
}
