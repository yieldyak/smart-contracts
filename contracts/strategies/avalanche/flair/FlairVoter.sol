// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../../interfaces/IWAVAX.sol";
import "../../../interfaces/IERC20.sol";
import "../../../interfaces/IERC721Receiver.sol";
import "../../../lib/Ownable.sol";

import "./interfaces/IVotingEscrow.sol";
import "./interfaces/IFlairVoter.sol";

/**
 * @notice FlairVoter manages deposits for other strategies
 * using a proxy pattern.
 */
contract FlairVoter is IFlairVoter, Ownable, IERC721Receiver {
    IWAVAX private constant WAVAX = IWAVAX(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);
    uint256 private constant MAX_LOCK = 4 * 365 * 86400;

    IVotingEscrow public constant ESCROW = IVotingEscrow(0x287E241DEcB03110e4bdbFcB554b962a19e0011f);
    address public constant FLDX = 0x107D2b7C619202D994a4d044c762Dd6F8e0c5326;

    address public voterProxy;
    bool public override depositsEnabled;
    uint256 public tokenId;

    modifier onlyFlairVoterProxy() {
        require(msg.sender == voterProxy, "FlairVoter::onlyFlairVoterProxy");
        _;
    }

    constructor(address _owner) {
        transferOwnership(_owner);
    }

    receive() external payable {}

    /**
     * @notice Update proxy address
     * @dev Very sensitive, restricted to owner
     * @param _voterProxy new address
     */
    function setVoterProxy(address _voterProxy) external override onlyOwner {
        voterProxy = _voterProxy;
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

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /**
     * @notice External deposit function for FLDX
     * @param _amount to deposit
     */
    function deposit(uint256 _amount) external override {
        require(depositsEnabled, "FlairVoter:deposits disabled");
        require(IERC20(FLDX).transferFrom(msg.sender, address(this), _amount), "FlairVoter::transfer failed");
        _deposit(_amount);
    }

    /**
     * @notice Deposit function for FLDX
     * @dev Restricted to proxy
     * @param _amount to deposit
     */
    function depositFromBalance(uint256 _amount) external override onlyFlairVoterProxy {
        _deposit(_amount);
    }

    /**
     * @notice Deposits and locks FLDX
     * @param _amount to deposit
     */
    function _deposit(uint256 _amount) internal {
        IERC20(FLDX).approve(address(ESCROW), _amount);
        uint256 id = tokenId;
        IVotingEscrow.LockedBalance memory lockedBalance = ESCROW.locked(id);
        if (id == 0) {
            tokenId = ESCROW.createLock(_amount, MAX_LOCK);
        } else if (lockedBalance.end < block.timestamp) {
            ESCROW.withdraw(tokenId);
            uint256 balance = IERC20(FLDX).balanceOf(address(this));
            IERC20(FLDX).approve(address(ESCROW), balance);
            tokenId = ESCROW.createLock(balance, MAX_LOCK);
        } else {
            ESCROW.increaseAmount(id, _amount);
            uint256 maxUnlockTimeRounded = (block.timestamp + MAX_LOCK) / 1 weeks * 1 weeks;
            if (maxUnlockTimeRounded > lockedBalance.end) {
                ESCROW.increaseUnlockTime(id, MAX_LOCK);
            }
        }
    }

    /**
     * @notice Helper function to wrap AVAX
     * @return amount wrapped to WAVAX
     */
    function wrapAVAXBalance() external override onlyFlairVoterProxy returns (uint256) {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            WAVAX.deposit{value: balance}();
        }
        return balance;
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
    function execute(address target, uint256 value, bytes calldata data)
        external
        override
        onlyFlairVoterProxy
        returns (bool, bytes memory)
    {
        (bool success, bytes memory result) = target.call{value: value}(data);

        return (success, result);
    }
}
