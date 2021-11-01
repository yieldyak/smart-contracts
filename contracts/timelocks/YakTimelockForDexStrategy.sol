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

    function updateReinvestReward(uint256 newValue) external;

    function recoverERC20(address tokenAddress, uint256 tokenAmount) external;

    function recoverAVAX(uint256 amount) external;
}

contract YakTimelockForDexStrategy {
    uint256 public constant timelockLengthForAssetRecovery = 2 days;
    uint256 public constant timelockLengthForOwnershipTransfer = 7 days;
    uint256 public constant timelockLengthForFeeChanges = 6 hours;

    address public manager;
    address public feeCollector;
    IStrategy public strategy;

    address public pendingOwner;
    uint256 public pendingAdminFee;
    uint256 public pendingReinvestReward;
    address public pendingTokenAddressToRecover;
    uint256 public pendingTokenAmountToRecover;
    uint256 public pendingAVAXToRecover;

    event ProposeOwner(address indexed proposedValue, uint256 timelock);
    event ProposeAdminFee(uint256 proposedValue, uint256 timelock);
    event ProposeReinvestReward(uint256 proposedValue, uint256 timelock);
    event ProposeRecovery(address indexed proposedToken, uint256 proposedValue, uint256 timelock);

    event SetOwner(address indexed newOwner);
    event SetAdminFee(uint256 newValue);
    event SetReinvestReward(uint256 newValue);
    event SetMinTokensToReinvest(uint256 newValue);
    event Sweep(address indexed token, uint256 amount);
    event Recover(address indexed token, uint256 amount);
    event EmergencyWithdraw();

    enum Functions {
        renounceOwnership,
        transferOwnership,
        emergencyWithdraw,
        updateMinTokensToReinvest,
        updateAdminFee,
        updateReinvestReward,
        recoverERC20,
        recoverAVAX
    }

    mapping(Functions => uint256) public timelock;

    constructor(address _strategy) {
        manager = msg.sender;
        feeCollector = msg.sender;
        strategy = IStrategy(_strategy);
    }

    // Modifiers

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
     * @param _fn Function enum value
     * @param timelockLength in seconds
     */
    modifier setTimelock(Functions _fn, uint256 timelockLength) {
        timelock[_fn] = block.timestamp + timelockLength;
        _;
    }

    /**
     * @notice Enforce timelock for a given function
     * @dev Ends execution by resetting timelock to avoid replay
     * @param _fn Function enum value
     */
    modifier enforceTimelock(Functions _fn) {
        require(timelock[_fn] != 0 && timelock[_fn] <= block.timestamp, "YakTimelockManagerV1::enforceTimelock");
        _;
        timelock[_fn] = 0;
    }

    /**
     * @notice Sweep tokens from the timelock to `feeCollector`
     * @dev The timelock contract may receive assets from both revenue and asset recovery.
     * @dev The sweep function is NOT timelocked, because recovered assets must go through separate timelock functions.
     * @param tokenAddress address
     * @param tokenAmount amount
     */
    function sweepTokens(address tokenAddress, uint256 tokenAmount) external onlyFeeCollector {
        require(tokenAmount > 0, "YakTimelockManagerV1::sweepTokens, amount too low");
        require(
            IERC20(tokenAddress).transfer(msg.sender, tokenAmount),
            "YakTimelockManagerV1::sweepTokens, transfer failed"
        );
        emit Sweep(tokenAddress, tokenAmount);
    }

    /**
     * @notice Sweep AVAX from the timelock to the `feeCollector` address
     * @dev The timelock contract may receive assets from both revenue and asset recovery.
     * @dev The sweep function is NOT timelocked, because recovered assets must go through separate timelock functions.
     * @param amount amount
     */
    function sweepAVAX(uint256 amount) external onlyFeeCollector {
        require(amount > 0, "YakTimelockManagerV1::sweepAVAX, amount too low");
        msg.sender.transfer(amount);
        emit Sweep(address(0), amount);
    }

    // Functions with timelocks

    /**
     * @notice Pass new value of `owner` through timelock
     * @dev Restricted to `manager` to avoid griefing
     * @dev Resets timelock duration through modifier
     * @param _pendingOwner new value
     */
    function proposeOwner(address _pendingOwner)
        external
        onlyManager
        setTimelock(Functions.transferOwnership, timelockLengthForOwnershipTransfer)
    {
        pendingOwner = _pendingOwner;
        emit ProposeOwner(_pendingOwner, timelock[Functions.transferOwnership]);
    }

    /**
     * @notice Set new value of `owner` and resets timelock
     * @dev This can be called by anyone
     */
    function setOwner() external enforceTimelock(Functions.transferOwnership) {
        strategy.transferOwnership(pendingOwner);
        emit SetOwner(pendingOwner);
        pendingOwner = address(0);
    }

    /**
     * @notice Pass new value of `adminFee` through timelock
     * @dev Restricted to `manager` to avoid griefing
     * @dev Resets timelock duration through modifier
     * @param _pendingAdminFee new value
     */
    function proposeAdminFee(uint256 _pendingAdminFee)
        external
        onlyManager
        setTimelock(Functions.updateAdminFee, timelockLengthForFeeChanges)
    {
        pendingAdminFee = _pendingAdminFee;
        emit ProposeAdminFee(_pendingAdminFee, timelock[Functions.updateAdminFee]);
    }

    /**
     * @notice Set new value of `adminFee` and reset timelock
     * @dev This can be called by anyone
     */
    function setAdminFee() external enforceTimelock(Functions.updateAdminFee) {
        strategy.updateAdminFee(pendingAdminFee);
        emit SetAdminFee(pendingAdminFee);
        pendingAdminFee = 0;
    }

    /**
     * @notice Pass new value of `reinvestReward` through timelock
     * @dev Restricted to `manager` to avoid griefing
     * @dev Resets timelock duration through modifier
     * @param _pendingReinvestReward new value
     */
    function proposeReinvestReward(uint256 _pendingReinvestReward)
        external
        onlyManager
        setTimelock(Functions.updateReinvestReward, timelockLengthForFeeChanges)
    {
        pendingReinvestReward = _pendingReinvestReward;
        emit ProposeReinvestReward(_pendingReinvestReward, timelock[Functions.updateReinvestReward]);
    }

    /**
     * @notice Set new value of `reinvestReward` and reset timelock
     * @dev This can be called by anyone
     */
    function setReinvestReward() external enforceTimelock(Functions.updateReinvestReward) {
        strategy.updateReinvestReward(pendingReinvestReward);
        emit SetReinvestReward(pendingReinvestReward);
        pendingReinvestReward = 0;
    }

    /**
     * @notice Pass values for `recoverERC20` through timelock
     * @dev Restricted to `manager` to avoid griefing
     * @dev Resets timelock duration through modifier
     * @param _pendingTokenAddressToRecover address
     * @param _pendingTokenAmountToRecover amount
     */
    function proposeRecoverERC20(address _pendingTokenAddressToRecover, uint256 _pendingTokenAmountToRecover)
        external
        onlyManager
        setTimelock(Functions.recoverERC20, timelockLengthForAssetRecovery)
    {
        pendingTokenAddressToRecover = _pendingTokenAddressToRecover;
        pendingTokenAmountToRecover = _pendingTokenAmountToRecover;
        emit ProposeRecovery(
            _pendingTokenAddressToRecover,
            _pendingTokenAmountToRecover,
            timelock[Functions.recoverERC20]
        );
    }

    /**
     * @notice Call `recoverERC20` and reset timelock
     * @dev This can be called by anyone
     * @dev Recoverd funds are collected to this timelock and may be swept
     */
    function setRecoverERC20() external enforceTimelock(Functions.recoverERC20) {
        strategy.recoverERC20(pendingTokenAddressToRecover, pendingTokenAmountToRecover);
        emit Recover(pendingTokenAddressToRecover, pendingTokenAmountToRecover);
        pendingTokenAddressToRecover = address(0);
        pendingTokenAmountToRecover = 0;
    }

    /**
     * @notice Pass values for `recoverAVAX` through timelock
     * @dev Restricted to `manager` to avoid griefing
     * @dev Resets timelock duration through modifier
     * @param _pendingAVAXToRecover amount
     */
    function proposeRecoverAVAX(uint256 _pendingAVAXToRecover)
        external
        onlyManager
        setTimelock(Functions.recoverAVAX, timelockLengthForAssetRecovery)
    {
        pendingAVAXToRecover = _pendingAVAXToRecover;
        emit ProposeRecovery(address(0), _pendingAVAXToRecover, timelock[Functions.recoverAVAX]);
    }

    /**
     * @notice Call `recoverAVAX` and reset timelock
     * @dev This can be called by anyone
     * @dev Recoverd funds are collected to this timelock and may be swept
     */
    function setRecoverAVAX() external enforceTimelock(Functions.recoverAVAX) {
        strategy.recoverAVAX(pendingAVAXToRecover);
        emit Recover(address(0), pendingAVAXToRecover);
        pendingAVAXToRecover = 0;
    }

    // Functions without timelocks

    /**
     * @notice Set new value of `minTokensToReinvest`
     * @dev Restricted to `manager` to avoid griefing
     * @param minTokensToReinvest new value
     */
    function setMinTokensToReinvest(uint256 minTokensToReinvest) external onlyManager {
        strategy.updateMinTokensToReinvest(minTokensToReinvest);
        emit SetMinTokensToReinvest(minTokensToReinvest);
    }

    /**
     * @notice Rescues deployed assets to the strategy contract
     * @dev Restricted to `manager` to avoid griefing
     * @dev In case of emergency, assets will be transferred to the timelock and may be swept
     */
    function emergencyWithdraw() external onlyManager {
        strategy.emergencyWithdraw();
        emit EmergencyWithdraw();
    }
}
