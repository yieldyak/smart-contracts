// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../../interfaces/IWAVAX.sol";
import "../../../lib/Ownable.sol";
import "../../../lib/ERC20.sol";

import "./interfaces/IVeJoeStaking.sol";
import "./interfaces/IJoeVoter.sol";

/**
 * @notice JoeVoter manages deposits for other strategies
 * using a proxy pattern. It also directly accepts deposits
 * in exchange for yyJOE token.
 */
contract JoeVoter is IJoeVoter, Ownable, ERC20 {
    IWAVAX private constant WAVAX = IWAVAX(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);
    address public constant JOE = address(0x6e84a6216eA6dACC71eE8E6b0a5B7322EEbC0fDd);
    IERC20 public constant veJOE = IERC20(0x3cabf341943Bc8466245e4d6F1ae0f8D071a1456);

    IVeJoeStaking public stakingContract;

    address public voterProxy;
    bool public override depositsEnabled = true;

    modifier onlyJoeVoterProxy() {
        require(msg.sender == voterProxy, "JoeVoter::onlyJoeVoterProxy");
        _;
    }

    constructor(address _owner, address _stakingContract) ERC20("Yield Yak JOE", "yyJOE") {
        stakingContract = IVeJoeStaking(_stakingContract);
        transferOwnership(_owner);
    }

    receive() external payable {}

    /**
     * @notice veJOE balance
     * @return uint256 balance
     */
    function veJOEBalance() external view override returns (uint256) {
        return veJOE.balanceOf(address(this));
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
     * @notice External deposit function for JOE
     * @param _amount to deposit
     */
    function deposit(uint256 _amount) external override {
        require(depositsEnabled == true, "JoeVoter::deposits disabled");
        require(IERC20(JOE).transferFrom(msg.sender, address(this), _amount), "JoeVoter::transfer failed");
        _deposit(_amount);
    }

    /**
     * @notice Update VeJoeStaking address
     * @param _stakingContract new address
     */
    function setStakingContract(address _stakingContract) external override onlyOwner {
        stakingContract = IVeJoeStaking(_stakingContract);
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
     * @notice Update veJOE balance
     * @dev Any one may call this
     */
    function claimVeJOE() external override {
        stakingContract.claim();
    }

    /**
     * @notice Deposit function for JOE
     * @dev Restricted to proxy
     * @param _amount to deposit
     */
    function depositFromBalance(uint256 _amount) external override onlyJoeVoterProxy {
        require(depositsEnabled == true, "JoeVoter:deposits disabled");
        _deposit(_amount);
    }

    /**
     * @notice Deposits JOE and mints yyJOE at 1:1 ratio
     * @param _amount to deposit
     */
    function _deposit(uint256 _amount) internal {
        IERC20(JOE).approve(address(stakingContract), _amount);
        _mint(msg.sender, _amount);
        stakingContract.deposit(_amount);
        IERC20(JOE).approve(address(stakingContract), 0);
    }

    /**
     * @notice Helper function to wrap AVAX
     * @return amount wrapped to WAVAX
     */
    function wrapAvaxBalance() external override onlyJoeVoterProxy returns (uint256) {
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
    ) external override onlyJoeVoterProxy returns (bool, bytes memory) {
        (bool success, bytes memory result) = target.call{value: value}(data);

        return (success, result);
    }
}
