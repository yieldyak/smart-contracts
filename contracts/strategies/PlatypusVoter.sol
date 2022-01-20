// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

import "../interfaces/IWAVAX.sol";
import "../interfaces/IVePTP.sol";
import "../lib/SafeERC20.sol";
import "../lib/Ownable.sol";
import "../lib/ERC20.sol";

contract PlatypusVoter is Ownable, ERC20 {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IWAVAX private constant WAVAX = IWAVAX(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);
    address public constant PTP = address(0x22d4002028f537599bE9f666d1c4Fa138522f9c8);
    IVePTP public constant vePTP = IVePTP(0x5857019c749147EEE22b1Fe63500F237F3c1B692);

    address public immutable devAddr;
    address public voterProxy;
    bool public depositsEnabled;

    modifier onlyDev() {
        require(msg.sender == devAddr, "PlatypusVoter::onlyDev");
        _;
    }

    modifier onlyPlatypusVoterProxy() {
        require(msg.sender == voterProxy, "PlatypusVoter::onlyPlatypusVoterProxy");
        _;
    }

    modifier onlyPlatypusVoterProxyOrDev() {
        require(msg.sender == voterProxy || msg.sender == devAddr, "PlatypusVoter:onlyPlatypusVoterProxyOrDev");
        _;
    }

    constructor(
        address _timelock,
        address _devAddr,
        bool _depositsEnabled
    ) ERC20("Yield Yak PTP", "yyPTP") {
        devAddr = _devAddr;
        transferOwnership(_timelock);
        depositsEnabled = _depositsEnabled;
    }

    receive() external payable {}

    function vePTPBalance() public view returns (uint256) {
        return vePTP.balanceOf(address(this));
    }

    function setDepositsEnabled(bool _depositsEnabled) external onlyDev {
        depositsEnabled = _depositsEnabled;
    }

    function deposit(uint256 _amount) public {
        require(depositsEnabled == true, "PlatypusVoter:deposits disabled");
        require(IERC20(PTP).transferFrom(msg.sender, address(this), _amount), "PlatypusVoter::transfer failed");
        _deposit(_amount);
    }

    function setVoterProxy(address _voterProxy) external onlyOwner {
        voterProxy = _voterProxy;
    }

    function claimVePTP() external onlyPlatypusVoterProxyOrDev {
        vePTP.claim();
    }

    function depositFromBalance(uint256 _amount) external onlyPlatypusVoterProxy {
        require(depositsEnabled == true, "PlatypusVoter:deposits disabled");
        _deposit(_amount);
    }

    function _deposit(uint256 _amount) internal {
        IERC20(PTP).safeApprove(address(vePTP), _amount);
        _mint(msg.sender, _amount);
        vePTP.deposit(_amount);
        IERC20(PTP).safeApprove(address(vePTP), 0);
    }

    function wrapAvaxBalance() external onlyPlatypusVoterProxy returns (uint256) {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            WAVAX.deposit{value: balance}();
        }
        return balance;
    }

    function execute(
        address target,
        uint256 value,
        bytes calldata data
    ) external onlyPlatypusVoterProxy returns (bool, bytes memory) {
        (bool success, bytes memory result) = target.call{value: value}(data);

        return (success, result);
    }
}
