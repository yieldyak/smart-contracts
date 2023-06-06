// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./lib/SafeMath.sol";
import "./lib/AccessControl.sol";
import "./timelocks/YakFeeCollectorV1.sol";
import "./interfaces/IWGAS.sol";

/**
 * @notice YakARC is an Automated Revenue Collector
 * @dev Includes public function to distribute all WAVAX and AVAX to designated payees
 * @dev Epochs are used to stagger distributions
 */
contract YakARC is AccessControl {
    using SafeMath for uint256;

    /// @notice Role to sweep funds from this contract (excluding AVAX/WAVAX)
    bytes32 public constant TOKEN_SWEEPER_ROLE = keccak256("TOKEN_SWEEPER_ROLE");

    /// @notice Role to update payees and ratio of payments
    bytes32 public constant DISTRIBUTION_UPDATER_ROLE = keccak256("DISTRIBUTION_UPDATER_ROLE");

    /// @dev WAVAX
    IWGAS private constant WAVAX = IWGAS(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);

    /// @notice YakFeeCollectorV1 address
    YakFeeCollectorV1 public feeCollector;

    /// @notice Epoch of the last distribution
    uint256 public lastPaymentEpoch;

    /// @notice Start time of the first epoch
    uint256 public immutable startTimestamp;

    /// @notice Minimum time between distributions
    uint256 public constant epochLength = 86400; // 24 hours

    /// @notice Array of payees. Upgradable
    address[] public distributionAddresses;

    /// @notice Array of payment ratios. Denominated in bips. Must sum to 10000 (100%). Upgradable
    uint256[] public distributionRatios;

    event Sweep(address indexed sweeper, address token, uint256 amount);
    event Paid(uint256 indexed epoch, address indexed payee, uint256 amount);
    event Distribution(uint256 indexed epoch, address indexed by, uint256 amount);
    event UpdateDistributions(address[] payee, uint256[] ratioBips);

    constructor(
        address _manager,
        address _tokenSweeper,
        address _upgrader,
        address payable _feeCollector,
        address[] memory _distributionAddresses,
        uint256[] memory _distributionRatios,
        uint256 _startTimestamp
    ) {
        _setupRole(DEFAULT_ADMIN_ROLE, _manager);
        _setupRole(TOKEN_SWEEPER_ROLE, _tokenSweeper);
        _setupRole(DISTRIBUTION_UPDATER_ROLE, _upgrader);

        feeCollector = YakFeeCollectorV1(_feeCollector);
        _updateDistributions(_distributionAddresses, _distributionRatios);
        require(_startTimestamp <= block.timestamp, "constructor");
        startTimestamp = _startTimestamp;
    }

    function getDistributionLength() public view returns (uint256) {
        return distributionAddresses.length;
    }

    /**
     * @notice Current distribution epoch
     * @return number of current epoch
     */
    function currentEpoch() public view returns (uint256) {
        return block.timestamp.sub(startTimestamp).div(epochLength);
    }

    /**
     * @notice When the next distribution is allowed occur
     * @return timestamp of next epoch
     */
    function nextEpoch() public view returns (uint256) {
        return startTimestamp.add(lastPaymentEpoch.add(1).mul(epochLength));
    }

    /**
     * @notice Current feeCollector balance in WAVAX+AVAX
     * @return balance
     */
    function currentBalance() external view returns (uint256) {
        return WAVAX.balanceOf(address(feeCollector)).add(address(feeCollector).balance);
    }

    function _sweepWAVAX() internal {
        uint256 balance = WAVAX.balanceOf(address(feeCollector));
        if (balance > 0) {
            feeCollector.sweepTokens(address(WAVAX), balance);
        }
    }

    function _sweepAVAX() internal {
        uint256 balance = address(feeCollector).balance;
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
        uint256 balance = address(this).balance;
        uint256 totalPaid;
        for (uint256 i; i < distributionAddresses.length; i++) {
            uint256 amount = balance.mul(distributionRatios[i]).div(10000);
            if (amount > 0) {
                totalPaid = totalPaid.add(amount);
                (bool success,) = distributionAddresses[i].call{value: amount}("");
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
    function sweepTokens(address tokenAddress, uint256 tokenAmount) external {
        require(hasRole(TOKEN_SWEEPER_ROLE, msg.sender), "sweepTokens::auth");
        require(tokenAddress != address(WAVAX), "sweepTokens::not allowed");
        feeCollector.sweepTokens(tokenAddress, tokenAmount);
        uint256 balance = IERC20(tokenAddress).balanceOf(address(this));
        if (balance < tokenAmount) {
            tokenAmount = balance;
        }
        require(IERC20(tokenAddress).transfer(msg.sender, tokenAmount), "sweepTokens::transfer failed");
        emit Sweep(msg.sender, tokenAddress, tokenAmount);
    }

    function _updateDistributions(address[] memory addresses, uint256[] memory ratioBips) private {
        require(addresses.length == ratioBips.length, "_updateDistributions::different lengths");
        uint256 sum;
        for (uint256 i; i < addresses.length; i++) {
            sum = sum.add(ratioBips[i]);
        }
        require(sum == 10000, "_updateDistributions::invalid ratioBips");
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
    function updateDistributions(address[] calldata addresses, uint256[] calldata ratioBips) external {
        require(hasRole(DISTRIBUTION_UPDATER_ROLE, msg.sender), "updateDistributions::auth");
        _updateDistributions(addresses, ratioBips);
    }

    receive() external payable {}
}
