// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../../lib/SafeERC20.sol";
import "../../../lib/AccessControl.sol";
import "../../../interfaces/IBoosterFeeCollector.sol";
import "./interfaces/IGlacierVoter.sol";
import "./interfaces/IGlacierGaugeVoter.sol";

library SafeProxy {
    function safeExecute(IGlacierVoter voter, address target, uint256 value, bytes memory data)
        internal
        returns (bytes memory)
    {
        (bool success, bytes memory returnValue) = voter.execute(target, value, data);
        if (!success) revert("GlacierBoosterFeeCollector::safeExecute failed");
        return returnValue;
    }
}

/**
 * @notice GlacierBoosterFeeCollector is an upgradable contract.
 * It collects an additional fee from Glacier strategies to accumulate veGLCR
 */
contract GlacierBoosterFeeCollector is AccessControl, IBoosterFeeCollector {
    using SafeProxy for IGlacierVoter;
    using SafeERC20 for IERC20;

    struct Reward {
        address reward;
        uint256 amount;
    }

    uint256 internal constant BIPS_DIVISOR = 10000;
    address internal constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    address internal constant GLCR = 0x3712871408a829C5cd4e86DA1f4CE727eFCD28F6;
    address internal constant GAUGE_VOTER = 0x4199Cf7D3cd8F92BAFBB97fF66caE507888b01F9;

    IGlacierVoter public immutable voter;

    mapping(address => uint256) public boostFeeBips;
    bool public paused = false;

    /// @notice Role to vote for gauge voting
    bytes32 public constant VOTING_ROLE = keccak256("VOTING_ROLE");

    /// @notice Role to manage booster fees per strategy
    bytes32 public constant FEE_SETTER_ROLE = keccak256("FEE_SETTER_ROLE");

    /// @notice Role to sweep funds from this contract
    bytes32 public constant TOKEN_SWEEPER_ROLE = keccak256("TOKEN_SWEEPER_ROLE");

    event Paused(bool paused);
    event BoostFeeUpdated(address strategy, uint256 oldValue, uint256 newValue);
    event Sweep(address indexed sweeper, address indexed token, uint256 amount);

    constructor(address _team, address _deployer, address _treasury, address _voting, address _voter) {
        _setupRole(FEE_SETTER_ROLE, _deployer);
        _setupRole(FEE_SETTER_ROLE, _team);
        _setupRole(TOKEN_SWEEPER_ROLE, _treasury);
        _setupRole(VOTING_ROLE, _voting);
        voter = IGlacierVoter(_voter);
    }

    function vote(address[] calldata _poolVote, uint256[] calldata _weights) external {
        require(hasRole(FEE_SETTER_ROLE, msg.sender), "BoosterFeeCollector::auth");
        voter.safeExecute(
            GAUGE_VOTER,
            0,
            abi.encodeWithSelector(IGlacierGaugeVoter.vote.selector, voter.tokenId(), _poolVote, _weights)
        );
    }

    /**
     * @notice Set boost fee in bips
     * @dev Restricted to `FEE_SETTER_ROLE`
     * @param _strategy address
     * @param _boostFeeBips boost fee in bips
     */
    function setBoostFee(address _strategy, uint256 _boostFeeBips) external override {
        require(hasRole(FEE_SETTER_ROLE, msg.sender), "BoosterFeeCollector::auth");
        require(_boostFeeBips <= BIPS_DIVISOR, "BoosterFeeCollector::Chosen boost fee too high");
        emit BoostFeeUpdated(_strategy, boostFeeBips[_strategy], _boostFeeBips);
        boostFeeBips[_strategy] = _boostFeeBips;
    }

    /**
     * @notice Set paused state
     * @dev Restricted to `FEE_SETTER_ROLE`
     * @dev In paused state, boost fee is zero for all strategies
     * @param _paused bool
     */
    function setPaused(bool _paused) external override {
        require(hasRole(FEE_SETTER_ROLE, msg.sender), "BoosterFeeCollector::auth");
        require(_paused != paused, "BoosterFeeCollector::already set");
        paused = _paused;
        emit Paused(_paused);
    }

    /**
     * @notice Collect ERC20 from this contract
     * @dev Restricted to `TOKEN_SWEEPER_ROLE`
     * @param tokenAddress address
     * @param tokenAmount amount
     */
    function sweepTokens(address tokenAddress, uint256 tokenAmount) external override {
        require(hasRole(TOKEN_SWEEPER_ROLE, msg.sender), "BoosterFeeCollector::auth");
        uint256 balance = IERC20(tokenAddress).balanceOf(address(this));
        if (balance < tokenAmount) {
            tokenAmount = balance;
        }
        require(tokenAmount > 0, "sweepTokens::balance");
        IERC20(tokenAddress).safeTransfer(msg.sender, tokenAmount);
        emit Sweep(msg.sender, tokenAddress, tokenAmount);
    }

    /**
     * @notice Calculate amount of tokens to hold as boost fee
     * @dev If the contract is paused, returns zero
     * @param _strategy address
     * @param _amount amount of tokens being reinvested
     * @return uint256 boost fee in tokens
     */
    function calculateBoostFee(address _strategy, uint256 _amount) external view override returns (uint256) {
        if (paused) return 0;
        uint256 boostFee = boostFeeBips[_strategy];
        return (_amount * boostFee) / BIPS_DIVISOR;
    }

    /**
     * @notice Convert PTP to yyPTP
     */
    function compound() external override {
        uint256 amount = IERC20(GLCR).balanceOf(address(this));
        IERC20(GLCR).safeTransfer(address(voter), amount);
        voter.depositFromBalance(amount);
    }
}
