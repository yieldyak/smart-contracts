// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;
import "../lib/AccessControl.sol";

contract TimelockRoleHelper is AccessControl{

    constructor() {}

    bytes32 public constant setTimelock_ADMIN = keccak256("setTimelock_ADMIN");
    bytes32 public constant allowDepositor_ADMIN = keccak256("allowDepositor_ADMIN");
    bytes32 public constant emergencyWithdraw_ADMIN = keccak256("emergencyWithdraw_ADMIN");
    bytes32 public constant proposeAdminFee_ADMIN = keccak256("proposeAdminFee_ADMIN");
    bytes32 public constant proposeDevFee_ADMIN = keccak256("proposeDevFee_ADMIN");
    bytes32 public constant proposeOwner_ADMIN = keccak256("proposeOwner_ADMIN");
    bytes32 public constant proposeRecoverAVAX_ADMIN = keccak256("proposeRecoverAVAX_ADMIN");
    bytes32 public constant proposeRecoverERC20_ADMIN = keccak256("proposeRecoverERC20_ADMIN");
    bytes32 public constant proposeReinvestReward_ADMIN = keccak256("proposeReinvestReward_ADMIN");
    bytes32 public constant removeDepositor_ADMIN = keccak256("removeDepositor_ADMIN");
    bytes32 public constant rescueDeployedFunds_ADMIN = keccak256("rescueDeployedFunds_ADMIN");
    bytes32 public constant setAdminFee_ADMIN = keccak256("setAdminFee_ADMIN");
    bytes32 public constant setAllowances_ADMIN = keccak256("setAllowances_ADMIN");
    bytes32 public constant setDepositsEnabled_ADMIN = keccak256("setDepositsEnabled_ADMIN");
    bytes32 public constant setDevFee_ADMIN = keccak256("setDevFee_ADMIN");
    bytes32 public constant setMaxTokensToDepositWithoutReinvest_ADMIN = keccak256("setMaxTokensToDepositWithoutReinvest_ADMIN");
    bytes32 public constant setMinTokensToReinvest_ADMIN = keccak256("setMinTokensToReinvest_ADMIN");
    bytes32 public constant setOwner_ADMIN = keccak256("setOwner_ADMIN");
    bytes32 public constant setRecoverAVAX_ADMIN = keccak256("setRecoverAVAX_ADMIN");
    bytes32 public constant setRecoverERC20_ADMIN = keccak256("setRecoverERC20_ADMIN");
    bytes32 public constant setReinvestReward_ADMIN = keccak256("setReinvestReward_ADMIN");
    bytes32 public constant sweepAVAX_ADMIN = keccak256("sweepAVAX_ADMIN");
    bytes32 public constant sweepTokens_ADMIN = keccak256("sweepTokens_ADMIN");

        // Modifiers

    /**
     * @notice Restrict to `setTimelock`
     * @dev To change, call revokeRole with setTimelock_ADMIN
     */
    modifier onlysetTimelock_ADMIN {
        require(hasRole(setTimelock_ADMIN, msg.sender), "Caller is not setTimelock_ADMIN");
        _;
    }

    /**
     * @notice Restrict to `allowDepositor`
     * @dev To change, call revokeRole with allowDepositor_ADMIN
     */
    modifier onlyallowDepositor_ADMIN {
        require(hasRole(allowDepositor_ADMIN, msg.sender), "Caller is not allowDepositor_ADMIN");
        _;
    }

    /**
     * @notice Restrict to `emergencyWithdraw`
     * @dev To change, call revokeRole with emergencyWithdraw_ADMIN
     */
    modifier onlyemergencyWithdraw_ADMIN {
        require(hasRole(emergencyWithdraw_ADMIN, msg.sender), "Caller is not emergencyWithdraw_ADMIN");
        _;
    }

    /**
     * @notice Restrict to `proposeAdminFee`
     * @dev To change, call revokeRole with proposeAdminFee_ADMIN
     */
    modifier onlyproposeAdminFee_ADMIN {
        require(hasRole(proposeAdminFee_ADMIN, msg.sender), "Caller is not proposeAdminFee_ADMIN");
        _;
    }

    /**
     * @notice Restrict to `proposeDevFee`
     * @dev To change, call revokeRole with proposeDevFee_ADMIN
     */
    modifier onlyproposeDevFee_ADMIN {
        require(hasRole(proposeDevFee_ADMIN, msg.sender), "Caller is not proposeDevFee_ADMIN");
        _;
    }

    /**
     * @notice Restrict to `proposeOwner`
     * @dev To change, call revokeRole with proposeOwner_ADMIN
     */
    modifier onlyproposeOwner_ADMIN {
        require(hasRole(proposeOwner_ADMIN, msg.sender), "Caller is not proposeOwner_ADMIN");
        _;
    }

    /**
     * @notice Restrict to `proposeRecoverAVAX`
     * @dev To change, call revokeRole with proposeRecoverAVAX_ADMIN
     */
    modifier onlyproposeRecoverAVAX_ADMIN {
        require(hasRole(proposeRecoverAVAX_ADMIN, msg.sender), "Caller is not proposeRecoverAVAX_ADMIN");
        _;
    }

    /**
     * @notice Restrict to `proposeRecoverERC20`
     * @dev To change, call revokeRole with proposeRecoverERC20_ADMIN
     */
    modifier onlyproposeRecoverERC20_ADMIN {
        require(hasRole(proposeRecoverERC20_ADMIN, msg.sender), "Caller is not proposeRecoverERC20_ADMIN");
        _;
    }

    /**
     * @notice Restrict to `proposeReinvestReward`
     * @dev To change, call revokeRole with proposeReinvestReward_ADMIN
     */
    modifier onlyproposeReinvestReward_ADMIN {
        require(hasRole(proposeReinvestReward_ADMIN, msg.sender), "Caller is not proposeReinvestReward_ADMIN");
        _;
    }

    /**
     * @notice Restrict to `removeDepositor`
     * @dev To change, call revokeRole with removeDepositor_ADMIN
     */
    modifier onlyremoveDepositor_ADMIN {
        require(hasRole(removeDepositor_ADMIN, msg.sender), "Caller is not removeDepositor_ADMIN");
        _;
    }

    /**
     * @notice Restrict to `rescueDeployedFunds`
     * @dev To change, call revokeRole with rescueDeployedFunds_ADMIN
     */
    modifier onlyrescueDeployedFunds_ADMIN {
        require(hasRole(rescueDeployedFunds_ADMIN, msg.sender), "Caller is not rescueDeployedFunds_ADMIN");
        _;
    }

    /**
     * @notice Restrict to `setAdminFee`
     * @dev To change, call revokeRole with setAdminFee_ADMIN
     */
    modifier onlysetAdminFee_ADMIN {
        require(hasRole(setAdminFee_ADMIN, msg.sender), "Caller is not setAdminFee_ADMIN");
        _;
    }

    /**
     * @notice Restrict to `setAllowances`
     * @dev To change, call revokeRole with setAllowances_ADMIN
     */
    modifier onlysetAllowances_ADMIN {
        require(hasRole(setAllowances_ADMIN, msg.sender), "Caller is not setAllowances_ADMIN");
        _;
    }

    /**
     * @notice Restrict to `setDepositsEnabled`
     * @dev To change, call revokeRole with setDepositsEnabled_ADMIN
     */
    modifier onlysetDepositsEnabled_ADMIN {
        require(hasRole(setDepositsEnabled_ADMIN, msg.sender), "Caller is not setDepositsEnabled_ADMIN");
        _;
    }

    /**
     * @notice Restrict to `setDevFee`
     * @dev To change, call revokeRole with setDevFee_ADMIN
     */
    modifier onlysetDevFee_ADMIN {
        require(hasRole(setDevFee_ADMIN, msg.sender), "Caller is not setDevFee_ADMIN");
        _;
    }

    /**
     * @notice Restrict to `setMaxTokensToDepositWithoutReinvest`
     * @dev To change, call revokeRole with setMaxTokensToDepositWithoutReinvest_ADMIN
     */
    modifier onlysetMaxTokensToDepositWithoutReinvest_ADMIN {
        require(hasRole(setMaxTokensToDepositWithoutReinvest_ADMIN, msg.sender), "Caller is not setMaxTokensToDepositWithoutReinvest_ADMIN");
        _;
    }

    /**
     * @notice Restrict to `setMinTokensToReinvest`
     * @dev To change, call revokeRole with setMinTokensToReinvest_ADMIN
     */
    modifier onlysetMinTokensToReinvest_ADMIN {
        require(hasRole(setMinTokensToReinvest_ADMIN, msg.sender), "Caller is not setMinTokensToReinvest_ADMIN");
        _;
    }

    /**
     * @notice Restrict to `setOwner`
     * @dev To change, call revokeRole with setOwner_ADMIN
     */
    modifier onlysetOwner_ADMIN {
        require(hasRole(setOwner_ADMIN, msg.sender), "Caller is not setOwner_ADMIN");
        _;
    }

    /**
     * @notice Restrict to `setRecoverAVAX`
     * @dev To change, call revokeRole with setRecoverAVAX_ADMIN
     */
    modifier onlysetRecoverAVAX_ADMIN {
        require(hasRole(setRecoverAVAX_ADMIN, msg.sender), "Caller is not setRecoverAVAX_ADMIN");
        _;
    }

    /**
     * @notice Restrict to `setRecoverERC20`
     * @dev To change, call revokeRole with setRecoverERC20_ADMIN
     */
    modifier onlysetRecoverERC20_ADMIN {
        require(hasRole(setRecoverERC20_ADMIN, msg.sender), "Caller is not setRecoverERC20_ADMIN");
        _;
    }

    /**
     * @notice Restrict to `setReinvestReward`
     * @dev To change, call revokeRole with setReinvestReward_ADMIN
     */
    modifier onlysetReinvestReward_ADMIN {
        require(hasRole(setReinvestReward_ADMIN, msg.sender), "Caller is not setReinvestReward_ADMIN");
        _;
    }

    /**
     * @notice Restrict to `sweepAVAX`
     * @dev To change, call revokeRole with sweepAVAX_ADMIN
     */
    modifier onlysweepAVAX_ADMIN {
        require(hasRole(sweepAVAX_ADMIN, msg.sender), "Caller is not sweepAVAX_ADMIN");
        _;
    }

    /**
     * @notice Restrict to `sweepTokens`
     * @dev To change, call revokeRole with sweepTokens_ADMIN
     */
    modifier onlysweepTokens_ADMIN {
        require(hasRole(sweepTokens_ADMIN, msg.sender), "Caller is not sweepTokens_ADMIN");
        _;
    }

}