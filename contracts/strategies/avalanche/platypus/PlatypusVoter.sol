// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../../interfaces/IWGAS.sol";
import "../../../lib/Ownable.sol";
import "../../../lib/ERC20.sol";
import "../../../lib/SafeERC20.sol";
import "../../../lib/SafeMath.sol";

import "./interfaces/IVePTP.sol";
import "./interfaces/IPlatypusVoter.sol";

/**
 * @notice PlatypusVoter manages deposits for other strategies
 * using a proxy pattern. It also directly accepts deposits
 * in exchange for yyPTP token.
 */
contract PlatypusVoter is IPlatypusVoter, Ownable, ERC20 {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IWGAS private constant WAVAX = IWGAS(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);
    address public constant PTP = address(0x22d4002028f537599bE9f666d1c4Fa138522f9c8);
    IVePTP public constant vePTP = IVePTP(0x5857019c749147EEE22b1Fe63500F237F3c1B692);

    address public voterProxy;
    bool public override depositsEnabled = true;

    modifier onlyPlatypusVoterProxy() {
        require(msg.sender == voterProxy, "PlatypusVoter::onlyPlatypusVoterProxy");
        _;
    }

    constructor(address _owner) ERC20("Yield Yak PTP", "yyPTP") {
        transferOwnership(_owner);
    }

    receive() external payable {}

    /**
     * @notice vePTP balance
     * @return uint256 balance
     */
    function vePTPBalance() external view override returns (uint256) {
        return vePTP.balanceOf(address(this));
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
     * @notice External deposit function for PTP
     * @param _amount to deposit
     */
    function deposit(uint256 _amount) external override {
        require(depositsEnabled == true, "PlatypusVoter:deposits disabled");
        require(IERC20(PTP).transferFrom(msg.sender, address(this), _amount), "PlatypusVoter::transfer failed");
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
     * @notice Update vePTP balance
     * @dev Any one may call this
     */
    function claimVePTP() external override {
        vePTP.claim();
    }

    /**
     * @notice Deposit function for PTP
     * @dev Restricted to proxy
     * @param _amount to deposit
     */
    function depositFromBalance(uint256 _amount) external override onlyPlatypusVoterProxy {
        require(depositsEnabled == true, "PlatypusVoter:deposits disabled");
        _deposit(_amount);
    }

    /**
     * @notice Deposits PTP and mints yyPTP at 1:1 ratio
     * @param _amount to deposit
     */
    function _deposit(uint256 _amount) internal {
        IERC20(PTP).safeApprove(address(vePTP), _amount);
        _mint(msg.sender, _amount);
        vePTP.deposit(_amount);
        IERC20(PTP).safeApprove(address(vePTP), 0);
    }

    /**
     * @notice Helper function to wrap AVAX
     * @return amount wrapped to WAVAX
     */
    function wrapAvaxBalance() external override onlyPlatypusVoterProxy returns (uint256) {
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
    function execute(
        address target,
        uint256 value,
        bytes calldata data
    ) external override onlyPlatypusVoterProxy returns (bool, bytes memory) {
        (bool success, bytes memory result) = target.call{value: value}(data);

        return (success, result);
    }
}
