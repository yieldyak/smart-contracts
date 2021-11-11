// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "./lib/SafeMath.sol";
import "./lib/AccessControl.sol";
import "./timelocks/YakFeeCollectorV1.sol";
import "./interfaces/IWAVAX.sol";

/**
 * @notice YakARC is an Automated Revenue Collector
 * @dev Includes public function to distribute all WAVAX and AVAX to designated payees
 * @dev Epochs are used to stagger distributions
 * @dev DRAFT
 */
contract YakARC is AccessControl {
    using SafeMath for uint;

    /// @notice Role to sweep funds from this contract (excluding AVAX/WAVAX)
    bytes32 public constant TOKEN_SWEEPER_ROLE = keccak256("TOKEN_SWEEPER_ROLE");

    /// @notice Role to update payees and ratio of payments
    bytes32 public constant DISTRIBUTION_UPDATER_ROLE = keccak256("DISTRIBUTION_UPDATER_ROLE");
    
    /// @dev WAVAX
    IWAVAX private constant WAVAX = IWAVAX(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);

    /// @notice YakFeeCollectorV1 address
    YakFeeCollectorV1 public feeCollector;

    /// @notice Epoch of the last distribution
    uint public lastPaymentEpoch;

    /// @notice Start time of the first epoch
    uimt public immutable startTimestamp;

    /// @notice Minimum time between distributions
    uint public constant epochLength = 86400; // 24 hours

    /// @notice Array of payees. Upgradable
    address[] public distributionAddresses;

    /// @notice Array of payment ratios. Denominated in bips. Must sum to 10000 (100%). Upgradable
    uint[] public distributionRatios;

    event Sweep(address indexed sweeper, address token, uint amount);
    event Paid(uint indexed epoch, address indexed payee, uint amount);
    event Distribution(uint indexed epoch, address indexed by, uint amount);
    event UpdateDistributions(address[] payee, uint[] ratioBips);

    constructor (
        address _manager,
        address _tokenSweeper,
        address _upgrader,
        address payable _feeCollector,
        address[] calldata distributionAddresses,
        address[] calldata distributionRatios,
        uint _startTimestamp
    ) {
        _setupRole(DEFAULT_ADMIN_ROLE, _manager);
        _setupRole(TOKEN_SWEEPER_ROLE, _tokenSweeper);
        _setupRole(DISTRIBUTION_UPDATER_ROLE, _upgrader);

        feeCollector = YakFeeCollectorV1(_feeCollector);
        _updateDistributions(distributionAddresses, distributionRatios);
        require(startTimestamp <= block.timestamp, "constructor");
        startTimestamp = _startTimestamp;
    }

    /**
     * @notice Current distribution epoch
     * @return number of current epoch
     */
    function currentEpoch() public view returns (uint) {
        return block.timestamp.sub(startTimestamp).div(epochLength);
    }

    /**
     * @notice When the next distribution is allowed occur
     * @return timestamp of next epoch
     */
    function nextEpoch() public view returns (uint) {
        return startTimestamp.add(lastPaymentEpoch.mul(epochLength));
    }

    /**
     * @notice Current feeCollector balance in WAVAX+AVAX
     * @return balance
     */
    function currentBalance() external view returns (uint) {
        return WAVAX.balanceOf(address(feeCollector)).add(address(feeCollector).balance);
    }

    function _sweepWAVAX() internal {
        uint balance = WAVAX.balanceOf(address(feeCollector));
        if (balance > 0) {
            feeCollector.sweepTokens(address(WAVAX), balance);
        }
    }

    function _sweepAVAX() internal {
        uint balance = address(feeCollector).balance;
        if (balance > 0) {
            feeCollector.sweepAVAX(balance);
        }
    }

    /**
     * @notice Distribute AVAX from this contract
     * @dev Open for anyone to call
     * @dev Sweeps available AVAX and WAVAX balances
     */
    function distribute() external {
        require(nextEpoch() <= block.timestamp, "distribute::too soon");
        _sweepAVAX();
        _sweepWAVAX();
        WAVAX.withdraw(WAVAX.balanceOf(address(this)));
        uint balance = address(this).balance;
        uint totalPaid;
        for (uint i; i < distributionAddresses.length; i++) {
            uint amount = balance.mul(distributionRatios[i]).div(10000);
            if (amount > 0) {
                totalPaid = totalPaid.add(amount);
                (bool success, ) = distributionAddresses[i].call{value: amount}("");
                require(success == true, "distribute::transfer failed");
                emit Paid(currentEpoch(), distributionAddresses[i], amount);
            }
        }
        emit Distribution(currentEpoch(), msg.sender, totalPaid);
        lastPaymentEpoch = currentEpoch();
    }

    /**
     * @notice Collect ERC20 from this contract
     * @dev Restricted to `TOKEN_SWEEPER_ROLE`
     * @dev This role is cannot sweep AVAX/WAVAX
     * @param tokenAddress address
     * @param tokenAmount amount
     */
    function sweepTokens(address tokenAddress, uint tokenAmount) external {
        require(hasRole(TOKEN_SWEEPER_ROLE, msg.sender), "sweepTokens::auth");
        require(tokenAddress != address(WAVAX), "sweepTokens::not allowed");
        uint balance = IERC20(tokenAddress).balanceOf(address(this));
        if (balance < tokenAmount) {
            tokenAmount = balance;
        }
        require(IERC20(tokenAddress).transfer(msg.sender, tokenAmount), "sweepTokens::transfer failed");
        emit Sweep(msg.sender, tokenAddress, tokenAmount);
    }

    function _updateDistributions(address[] calldata addresses, uint[] calldata ratioBips) private {
        require(addresses.length == ratioBips.length, "_updateDistributions::different lengths");
        uint targetSum = 10000;
        for (uint i = 0; i < addresses.length; i++) {
            targetSum = targetSum.sub(ratioBips[i]);
        }
        require(targetSum == 0, "_updateDistributions::invalid ratioBips");
        distributionAddresses = addresses;
        distributionRatios = ratioBips;
        emit UpdateDistributions(addresses, ratioBips);
    }

    /**
     * @notice Change payment distributions
     * @dev Restricted to `DISTRIBUTION_UPDATER_ROLE`
     * @param addresses payees
     * @param ratioBips payment ratios in bips, must add to 10000 // 100bps = 1%
     */
    function updateDistributions(address[] calldata addresses, uint[] calldata ratioBips) external {
        require(hasRole(DISTRIBUTION_UPDATER_ROLE, msg.sender), "updateDistributions::auth");
        _updateDistributions(addresses, ratioBips);
    }

    receive() external payable {}
}