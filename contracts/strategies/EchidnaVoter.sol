// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

import "../interfaces/IWAVAX.sol";
import "../interfaces/IEchidnaVoter.sol";
import "../interfaces/IVoteEscrow.sol";
import "../interfaces/IERC20.sol";
import "../lib/Ownable.sol";
import "hardhat/console.sol";

/**
 * @notice EchidnaVoter manages deposits for other strategies
 * using a proxy pattern.
 */
contract EchidnaVoter is Ownable, IEchidnaVoter {
    address public constant escrow = 0x721C2c768635D2b0147552861a0D8FDfde55C032;
    IERC20 private constant ECD = IERC20(0xeb8343D5284CaEc921F035207ca94DB6BAaaCBcd);
    uint256 private constant MAXTIME = 2 * 365 * 86400;
    uint256 private constant WEEK = 7 * 86400;

    address public voterProxy;
    bool private initialized;

    modifier onlyEchidnaVoterProxy() {
        require(msg.sender == voterProxy, "EchidnaVoter::onlyEchidnaVoterProxy");
        _;
    }

    constructor(address _owner) {
        transferOwnership(_owner);
    }

    /**
     * @notice veECD balance
     * @return balance int128
     */
    function veECDBalance() external view returns (int128 balance) {
        (balance, ) = IVoteEscrow(escrow).locked(address(this));
    }

    function lock() external override onlyEchidnaVoterProxy {
        if (initialized) {
            uint256 amount = ECD.balanceOf(address(this));
            ECD.approve(escrow, amount);
            IVoteEscrow(escrow).increase_amount(amount);
            ECD.approve(escrow, 0);
            (, uint256 currentUnlockTime) = IVoteEscrow(escrow).locked(address(this));
            uint256 unlockTime = block.timestamp + MAXTIME;
            if ((unlockTime / WEEK) * WEEK > currentUnlockTime) {
                IVoteEscrow(escrow).increase_unlock_time(unlockTime);
            }
        } else {
            initLock();
        }
    }

    function initLock() private {
        uint256 amount = ECD.balanceOf(address(this));
        uint256 unlockTime = block.timestamp + MAXTIME;
        ECD.approve(escrow, amount);
        IVoteEscrow(escrow).create_lock(amount, unlockTime);
        ECD.approve(escrow, 0);
        initialized = true;
    }

    /**
     * @notice Update proxy address
     * @dev Very sensitive, restricted to owner
     * @param _voterProxy new address
     */
    function setVoterProxy(address _voterProxy) external onlyOwner {
        voterProxy = _voterProxy;
    }

    /**
     * @notice Open-ended execute function
     * @dev Very sensitive, restricted to proxy
     * @param target address
     * @param value value to transfer
     * @param data calldata
     * @return bool success
     * @return bytes result
     */
    function execute(
        address target,
        uint256 value,
        bytes calldata data
    ) external override onlyEchidnaVoterProxy returns (bool, bytes memory) {
        (bool success, bytes memory result) = target.call{value: value}(data);

        return (success, result);
    }
}
