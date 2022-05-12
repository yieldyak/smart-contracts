// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../interfaces/IWAVAX.sol";
import "../../interfaces/IERC20.sol";
import "../../lib/Ownable.sol";
import "../../lib/ERC20.sol";

import "./interfaces/IYetiVoter.sol";
import "./interfaces/IVeYeti.sol";

/**
 * @notice YetiVoter manages deposits for other strategies
 * using a proxy pattern.
 */
contract YetiVoter is Ownable, IYetiVoter, ERC20 {
    address public constant VeYETI = 0x88888888847DF39Cf1dfe1a05c904b4E603C9416;
    IERC20 private constant YETI = IERC20(0x77777777777d4554c39223C354A05825b2E8Faa3);

    address public voterProxy;
    address public currentYetiRewarder;
    bool public override depositsEnabled = true;

    modifier onlyProxy() {
        require(msg.sender == voterProxy, "YetiVoter::onlyProxy");
        _;
    }

    constructor(address _owner) ERC20("Yield Yak YETI", "yyYETI") {
        transferOwnership(_owner);
    }

    /**
     * @notice veYETI balance
     * @return uint256 balance
     */
    function veYETIBalance() external view returns (uint256) {
        return IVeYeti(VeYETI).getTotalVeYeti(address(this));
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
     * @notice Update Yeti rewarder for which this contract accumulates veYETI
     * @dev Restricted to owner
     * @param _rewarder new address
     */
    function updateYetiRewarder(address _rewarder) external onlyOwner {
        currentYetiRewarder = _rewarder;
    }

    /**
     * @notice External deposit function for YETI
     * @param _amount to deposit
     */
    function deposit(uint256 _amount) external {
        require(depositsEnabled == true, "YetiVoter::deposits disabled");
        require(IERC20(YETI).transferFrom(msg.sender, address(this), _amount), "YetiVoter::transfer failed");
        _deposit(_amount);
    }

    function depositFromBalance(uint256 _amount) external override onlyProxy {
        require(depositsEnabled == true, "YetiVoter:deposits disabled");
        _deposit(_amount);
    }

    function _deposit(uint256 _amount) internal {
        _mint(msg.sender, _amount);

        YETI.approve(VeYETI, _amount);
        IVeYeti.RewarderUpdate[] memory rewarderUpdates = new IVeYeti.RewarderUpdate[](1);
        rewarderUpdates[0] = IVeYeti.RewarderUpdate({rewarder: currentYetiRewarder, amount: _amount, isIncrease: true});
        IVeYeti(VeYETI).update(rewarderUpdates);
        YETI.approve(VeYETI, 0);
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
