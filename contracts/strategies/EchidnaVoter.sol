// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

import "../interfaces/IEchidnaVoter.sol";
import "../interfaces/IVoteEscrow.sol";
import "../interfaces/IERC20.sol";
import "../lib/SafeERC20.sol";
import "../lib/SafeMath.sol";
import "../lib/Ownable.sol";
import "../lib/ERC20.sol";

/**
 * @notice EchidnaVoter manages deposits for other strategies
 * using a proxy pattern.
 */
contract EchidnaVoter is Ownable, IEchidnaVoter, ERC20 {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IVoteEscrow public constant ESCROW = IVoteEscrow(0x721C2c768635D2b0147552861a0D8FDfde55C032);
    IERC20 private constant ECD = IERC20(0xeb8343D5284CaEc921F035207ca94DB6BAaaCBcd);
    uint256 private constant MAXTIME = 2 * 365 * 86400;
    uint256 private constant WEEK = 7 * 86400;

    address public voterProxy;
    bool private initialized;
    bool public override depositsEnabled = true;

    modifier onlyProxy() {
        require(msg.sender == voterProxy, "EchidnaVoter::onlyProxy");
        _;
    }

    constructor(address _owner) ERC20("Yield Yak ECD", "yyECD") {
        transferOwnership(_owner);
    }

    /**
     * @notice veECD balance
     * @return uint256 balance
     */
    function veECDBalance() external view returns (uint256) {
        return ESCROW.balanceOf(address(this));
    }

    /**
     * @notice Enable/disable deposits
     * @dev Restricted to owner
     * @param newValue bool
     */
    function updateDepositsEnabled(bool newValue) external onlyOwner {
        require(depositsEnabled != newValue);
        depositsEnabled = newValue;
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
     * @notice External deposit function for ECD
     * @param _amount to deposit
     */
    function deposit(uint256 _amount) external {
        require(depositsEnabled == true, "EchidnaVoter::deposits disabled");
        require(ECD.transferFrom(msg.sender, address(this), _amount), "EchidnaVoter::transfer failed");
        _deposit(_amount);
    }

    function depositFromBalance(uint256 _amount) external override onlyProxy {
        require(depositsEnabled == true, "EchidnaVoter:deposits disabled");
        _deposit(_amount);
    }

    function _deposit(uint256 _amount) internal {
        _mint(msg.sender, _amount);

        if (initialized) {
            ECD.approve(address(ESCROW), _amount);
            ESCROW.increase_amount(_amount);
            ECD.approve(address(ESCROW), 0);
            (, uint256 currentUnlockTime) = ESCROW.locked(address(this));
            uint256 unlockTime = block.timestamp.add(MAXTIME);
            if (unlockTime.div(WEEK).mul(WEEK) > currentUnlockTime) {
                ESCROW.increase_unlock_time(unlockTime);
            }
        } else {
            _initLock(_amount);
        }
    }

    function _initLock(uint256 _amount) private {
        uint256 unlockTime = block.timestamp.add(MAXTIME);
        ECD.approve(address(ESCROW), _amount);
        ESCROW.create_lock(_amount, unlockTime);
        ECD.approve(address(ESCROW), 0);
        initialized = true;
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
    ) external override onlyProxy returns (bool, bytes memory) {
        (bool success, bytes memory result) = target.call{value: value}(data);

        return (success, result);
    }
}
