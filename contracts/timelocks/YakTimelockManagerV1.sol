// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

interface IStrategy {
    function owner() external view returns (address);
    function renounceOwnership() external;
    function transferOwnership(address newOwner) external;

    function depositToken() external view returns (address);
    function emergencyWithdraw() external;
    function updateMinTokensToReinvest(uint newValue) external;
    function updateAdminFee(uint newValue) external;
    function updateReinvestReward(uint newValue) external;
    function recoverERC20(address tokenAddress, uint tokenAmount) external;
    function recoverAVAX(uint amount) external;
}

contract YakTimelockManagerV1 {

    uint public constant timelockLengthForAssetRecovery = 2 days;
    uint public constant timelockLengthForOwnershipTransfer = 7 days;
    uint public constant timelockLengthForFeeChanges = 6 hours;

    address public manager;
    address public feeCollector;
    IStrategy public strategy;

    address public pendingOwner;
    uint public pendingAdminFee;
    uint public pendingReinvestReward;
    address public pendingTokenAddressToRecover;
    uint public pendingTokenAmountToRecover;
    uint public pendingAVAXToRecover;

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

    mapping(Functions => uint) public timelock;

    constructor(
        address _strategy
    ) {
        manager = msg.sender;
        feeCollector = msg.sender;
        strategy = IStrategy(_strategy);
    }

    // Modifiers

    /**
     * @notice Restrict to `manager`
     * @dev To change manager, deploy new timelock and transfer strategy ownership
     */
    modifier onlyManager {
        require(msg.sender == manager);
        _;
    }

    /**
     * @notice Restrict to `feeCollector`
     * @dev To change feeCollector, deploy new timelock and transfer strategy ownership
     */
    modifier onlyFeeCollector {
        require(msg.sender == feeCollector);
        _;
    }

    /**
     * @notice Set timelock when changing pending values
     * @param _fn Function enum value
     * @param timelockLength in seconds
     */
    modifier setTimelock(Functions _fn, uint timelockLength) {
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
    function sweepTokens(address tokenAddress, uint tokenAmount) external onlyFeeCollector {
        require(tokenAmount > 0, 'YakTimelockManagerV1::sweepTokens, amount too low');
        IERC20(tokenAddress).transfer(msg.sender, tokenAmount);
    }

    /**
     * @notice Sweep AVAX from the timelock to the `feeCollector` address
     * @dev The timelock contract may receive assets from both revenue and asset recovery.
     * @dev The sweep function is NOT timelocked, because recovered assets must go through separate timelock functions.
     * @param amount amount
     */
    function sweepAVAX(uint amount) external onlyFeeCollector {
        require(amount > 0, 'YakTimelockManagerV1::sweepAVAX, amount too low');
        msg.sender.transfer(amount);
    }

    // Functions with timelocks

    /**
     * @notice Pass new value of `owner` through timelock
     * @dev Restricted to `manager` to avoid griefing
     * @dev Resets timelock duration through modifier
     * @param _pendingOwner new value
     */
    function proposeOwner(address _pendingOwner) external onlyManager setTimelock(Functions.transferOwnership, timelockLengthForOwnershipTransfer) {
        pendingOwner = _pendingOwner;
    }

    /**
     * @notice Set new value of `owner` and resets timelock
     * @dev This can be called by anyone
     */
    function setOwner() external enforceTimelock(Functions.transferOwnership) {
        strategy.transferOwnership(pendingOwner);
        pendingOwner = address(0);
    }

    /**
     * @notice Pass new value of `adminFee` through timelock
     * @dev Restricted to `manager` to avoid griefing
     * @dev Resets timelock duration through modifier
     * @param _pendingAdminFee new value
     */
    function proposeAdminFee(uint _pendingAdminFee) external onlyManager setTimelock(Functions.updateAdminFee, timelockLengthForFeeChanges) {
        pendingAdminFee = _pendingAdminFee;
    }

    /**
     * @notice Set new value of `adminFee` and reset timelock
     * @dev This can be called by anyone
     */
    function setAdminFee() external enforceTimelock(Functions.updateAdminFee) {
        strategy.updateAdminFee(pendingAdminFee);
        pendingAdminFee = 0;
    }

    /**
     * @notice Pass new value of `reinvestReward` through timelock
     * @dev Restricted to `manager` to avoid griefing
     * @dev Resets timelock duration through modifier
     * @param _pendingReinvestReward new value
     */
    function proposeReinvestReward(uint _pendingReinvestReward) external onlyManager setTimelock(Functions.updateReinvestReward, timelockLengthForFeeChanges) {
        pendingReinvestReward = _pendingReinvestReward;
    }

    /**
     * @notice Set new value of `reinvestReward` and reset timelock
     * @dev This can be called by anyone
     */
    function setReinvestReward() external enforceTimelock(Functions.updateReinvestReward) {
        strategy.updateReinvestReward(pendingReinvestReward);
        pendingReinvestReward = 0;
    }

    /**
     * @notice Pass values for `recoverERC20` through timelock
     * @dev Restricted to `manager` to avoid griefing
     * @dev Resets timelock duration through modifier
     * @param _pendingTokenAddressToRecover address
     * @param _pendingTokenAmountToRecover amount
     */
    function proposeRecoverERC20(address _pendingTokenAddressToRecover, uint _pendingTokenAmountToRecover) external onlyManager setTimelock(Functions.recoverERC20, timelockLengthForAssetRecovery) {
        pendingTokenAddressToRecover = _pendingTokenAddressToRecover;
        pendingTokenAmountToRecover = _pendingTokenAmountToRecover;
    }

    /**
     * @notice Call `recoverERC20` and reset timelock
     * @dev This can be called by anyone
     * @dev Recoverd funds are collected to this timelock and may be swept
     */
    function setRecoverERC20() external enforceTimelock(Functions.recoverERC20) {
        strategy.recoverERC20(pendingTokenAddressToRecover, pendingTokenAmountToRecover);
        pendingTokenAddressToRecover = address(0);
        pendingReinvestReward = 0;
    }

    /**
     * @notice Pass values for `recoverAVAX` through timelock
     * @dev Restricted to `manager` to avoid griefing
     * @dev Resets timelock duration through modifier
     * @param _pendingAVAXToRecover amount
     */
    function proposeRecoverAVAX(uint _pendingAVAXToRecover) external onlyManager setTimelock(Functions.recoverAVAX, timelockLengthForAssetRecovery) {
        pendingAVAXToRecover = _pendingAVAXToRecover;
    }

    /**
     * @notice Call `recoverAVAX` and reset timelock
     * @dev This can be called by anyone
     * @dev Recoverd funds are collected to this timelock and may be swept
     */
    function setRecoverAVAX() external enforceTimelock(Functions.recoverAVAX) {
        strategy.recoverAVAX(pendingAVAXToRecover);
        pendingAVAXToRecover = 0;
    }

    // Functions without timelocks

    /**
     * @notice Set new value of `minTokensToReinvest`
     * @dev Restricted to `manager` to avoid griefing
     * @param minTokensToReinvest new value
     */
    function setMinTokensToReinvest(uint minTokensToReinvest) external onlyManager {
        strategy.updateMinTokensToReinvest(minTokensToReinvest);
    }

    /**
     * @notice Rescues deployed assets to the strategy contract
     * @dev Restricted to `manager` to avoid griefing
     * @dev In case of emergency, assets will be transferred to the timelock and may be swept
     */
    function emergencyWithdraw() external onlyManager {
        strategy.emergencyWithdraw();
    }
}