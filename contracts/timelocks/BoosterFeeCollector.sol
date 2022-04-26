// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

import "../interfaces/IPlatypusVoter.sol";
import "../interfaces/IBoosterFeeCollector.sol";
import "../lib/AccessControl.sol";
import "../lib/SafeERC20.sol";
import "../lib/SafeMath.sol";

/**
 * @notice Role-based manager for collecting boost fees
 * @dev Designed for compatibility with deployed YakStrategy and FeeCollector contracts
 */
contract BoosterFeeCollector is AccessControl, IBoosterFeeCollector {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 internal constant BIPS_DIVISOR = 10000;

    IERC20 public constant PTP = IERC20(0x22d4002028f537599bE9f666d1c4Fa138522f9c8);
    IPlatypusVoter public constant VOTER = IPlatypusVoter(0x40089e90156Fc6F994cc0eC86dbe84634A1C156F);

    mapping(address => uint256) public boostFeeBips;
    bool public paused = false;

    /// @notice Role to manage booster fees per strategy
    bytes32 public constant FEE_SETTER_ROLE = keccak256("FEE_SETTER_ROLE");

    /// @notice Role to sweep funds from this contract
    bytes32 public constant TOKEN_SWEEPER_ROLE = keccak256("TOKEN_SWEEPER_ROLE");

    event Paused(bool paused);
    event BoostFeeUpdated(address strategy, uint256 oldValue, uint256 newValue);
    event Sweep(address indexed sweeper, address indexed token, uint256 amount);

    constructor(
        address _team,
        address _deployer,
        address _treasury
    ) {
        _setupRole(FEE_SETTER_ROLE, _deployer);
        _setupRole(FEE_SETTER_ROLE, _team);
        _setupRole(TOKEN_SWEEPER_ROLE, _treasury);
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
     * @notice Calculate amount of tokens to hold as boost fee
     * @dev If the contract is paused, returns zero
     * @param _strategy address
     * @param _amount amount of tokens being reinvested
     * @return uint256 boost fee in tokens
     */
    function calculateBoostFee(address _strategy, uint256 _amount) external view override returns (uint256) {
        if (paused) return 0;
        uint256 boostFee = boostFeeBips[_strategy];
        return _amount.mul(boostFee).div(BIPS_DIVISOR);
    }

    /**
     * @notice Convert PTP to yyPTP
     */
    function compound() external override {
        uint256 amount = PTP.balanceOf(address(this));
        PTP.approve(address(VOTER), amount);
        VOTER.deposit(amount);
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
}
