// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../../interfaces/IWAVAX.sol";
import "../../../lib/Ownable.sol";
import "../../../lib/ERC20.sol";
import "../../../lib/SafeERC20.sol";

import "./interfaces/IVotingEscrow.sol";
import "./interfaces/IGlacierVoter.sol";
import "./interfaces/IERC721Receiver.sol";

/**
 * @notice GlacierVoter manages deposits for other strategies
 * using a proxy pattern. It also directly accepts GLCR deposits
 * in exchange for yyGLCR token.
 */
contract GlacierVoter is IGlacierVoter, Ownable, ERC20, IERC721Receiver {
    using SafeERC20 for IERC20;

    uint256 internal constant MAX_LOCK = 12 * 7 * 86400;

    IWAVAX private constant WAVAX = IWAVAX(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);
    IVotingEscrow public constant votingEscrow = IVotingEscrow(0xed1eE3f892fe8a13A9BE02F92E8FB7410AA84739);
    address public constant GLCR = 0x3712871408a829C5cd4e86DA1f4CE727eFCD28F6;

    address public voterProxy;
    bool public override depositsEnabled;
    uint256 public tokenId;

    modifier onlyGlacierVoterProxy() {
        require(msg.sender == voterProxy, "GlacierVoter::onlyGlacierVoterProxy");
        _;
    }

    constructor(address _owner) ERC20("Yield Yak Glacier", "yyGLCR") {
        transferOwnership(_owner);
    }

    receive() external payable {}

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
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
     * @notice External deposit function for GLCR
     * @param _amount to deposit
     */
    function deposit(uint256 _amount) external override {
        require(depositsEnabled == true, "GlacierVoter:deposits disabled");
        require(IERC20(GLCR).transferFrom(msg.sender, address(this), _amount), "GlacierVoter::transfer failed");
        _deposit(_amount);
    }

    /**
     * @notice Update proxy address
     * @dev Very sensitive, restricted to owner
     * @param _voterProxy new address
     */
    function setVoterProxy(address _voterProxy) external override onlyOwner {
        voterProxy = _voterProxy;
    }

    /**
     * @notice Deposit function for GLCR
     * @dev Restricted to proxy
     * @param _amount to deposit
     */
    function depositFromBalance(uint256 _amount) external override onlyGlacierVoterProxy {
        _deposit(_amount);
    }

    /**
     * @notice Deposits GLCR and mints yyGLCR at 1:1 ratio
     * @param _amount to deposit
     */
    function _deposit(uint256 _amount) internal {
        IERC20(GLCR).safeApprove(address(votingEscrow), _amount);
        _mint(msg.sender, _amount);
        uint256 id = tokenId;
        IVotingEscrow.LockedBalance memory lockedBalance = votingEscrow.locked(id);
        if (id == 0) {
            tokenId = votingEscrow.create_lock(_amount, MAX_LOCK);
        } else if (lockedBalance.end < block.timestamp) {
            votingEscrow.withdraw(tokenId);
            uint256 balance = IERC20(GLCR).balanceOf(address(this));
            IERC20(GLCR).safeApprove(address(votingEscrow), balance);
            tokenId = votingEscrow.create_lock(balance, MAX_LOCK);
        } else {
            votingEscrow.increase_amount(id, _amount);
            votingEscrow.increase_unlock_time(id, MAX_LOCK);
        }
    }

    /**
     * @notice Helper function to wrap AVAX
     * @return amount wrapped to WAVAX
     */
    function wrapEthBalance() external override onlyGlacierVoterProxy returns (uint256) {
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
        onlyGlacierVoterProxy
        returns (bool, bytes memory)
    {
        (bool success, bytes memory result) = target.call{value: value}(data);

        return (success, result);
    }
}
