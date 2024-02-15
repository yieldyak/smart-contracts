// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./../../../interfaces/IERC20.sol";
import "./interfaces/IWombatVoter.sol";
import "./interfaces/IBoostedMasterWombat.sol";
import "./interfaces/IWombatWaddle.sol";

interface IWombatStrategy {
    function pid() external view returns (uint256);
    function masterWombat() external view returns (address);
}

library SafeProxy {
    function safeExecute(IWombatVoter voter, address target, uint256 value, bytes memory data)
        internal
        returns (bytes memory)
    {
        (bool success, bytes memory returnValue) = voter.execute(target, value, data);
        if (!success) revert("WombatProxy::safeExecute failed");
        return returnValue;
    }
}

contract WombatProxy {
    using SafeProxy for IWombatVoter;

    struct Reward {
        address reward;
        uint256 amount;
    }

    uint256 constant LOCK_DAYS = 1461;
    uint256 internal constant BIPS_DIVISOR = 10000;

    address public devAddr;
    IWombatVoter public immutable voter;
    IWombatWaddle public immutable wombatWaddle;
    address immutable WOM;

    // staking contract => pid => strategy
    mapping(address => mapping(uint256 => address)) public approvedStrategies;
    uint256 boostFeeBips;
    uint256 minBoostAmount;

    modifier onlyDev() {
        require(msg.sender == devAddr, "WombatProxy::onlyDev");
        _;
    }

    modifier onlyStrategy(address _stakingContract, uint256 _pid) {
        require(approvedStrategies[_stakingContract][_pid] == msg.sender, "WombatProxy::onlyStrategy");
        _;
    }

    constructor(
        address _voter,
        address _devAddr,
        address _wombatWaddle,
        uint256 _boostFeeBips,
        uint256 _minBoostAmount
    ) {
        require(_devAddr > address(0), "WombatProxy::Invalid dev address provided");
        devAddr = _devAddr;
        voter = IWombatVoter(_voter);
        wombatWaddle = IWombatWaddle(_wombatWaddle);
        WOM = wombatWaddle.wom();
        boostFeeBips = _boostFeeBips;
        minBoostAmount = _minBoostAmount;
    }

    /**
     * @notice Update devAddr
     * @param newValue address
     */
    function updateDevAddr(address newValue) external onlyDev {
        devAddr = newValue;
    }

    /**
     * @notice Add an approved strategy
     * @dev Very sensitive, restricted to devAddr
     * @dev Can only be set once per PID and staking contract (reported by the strategy)
     * @param _strategy address
     */
    function approveStrategy(address _strategy) public onlyDev {
        uint256 pid = IWombatStrategy(_strategy).pid();
        address stakingContract = IWombatStrategy(_strategy).masterWombat();
        require(approvedStrategies[stakingContract][pid] == address(0), "WombatProxy::Strategy for PID already added");
        approvedStrategies[stakingContract][pid] = _strategy;
    }

    /**
     * @notice Transfer from _amount WOM from sender and lock for veWOM
     * @dev This contract needs approval to transfer _amount WOM before calling this method
     * @param _amount WOM amount
     */
    function boost(uint256 _amount) public onlyDev {
        IERC20(WOM).transferFrom(msg.sender, address(voter), _amount);
        _boost(_amount);
    }

    /**
     * @notice Update additional/optional boost fee settins
     * @param _boostFeeBips Boost fee bips, check BIPS_DIVISOR
     * @param _minBoostAmount Minimum amount of WOM to create a new lock position
     */
    function updateBoostFee(uint256 _boostFeeBips, uint256 _minBoostAmount) external onlyDev {
        require(_boostFeeBips < BIPS_DIVISOR, "WombatProxy::Invalid boost fee");
        boostFeeBips = _boostFeeBips;
        minBoostAmount = _minBoostAmount;
    }

    function depositToStakingContract(address _masterWombat, uint256 _pid, address _token, uint256 _amount)
        external
        onlyStrategy(_masterWombat, _pid)
    {
        voter.safeExecute(_token, 0, abi.encodeWithSelector(IERC20.approve.selector, _masterWombat, _amount));
        voter.safeExecute(
            _masterWombat, 0, abi.encodeWithSelector(IBoostedMasterWombat.deposit.selector, _pid, _amount)
        );
    }

    function withdrawFromStakingContract(address _masterWombat, uint256 _pid, address _token, uint256 _amount)
        external
        onlyStrategy(_masterWombat, _pid)
    {
        getRewards(_masterWombat, _pid);
        voter.safeExecute(
            _masterWombat, 0, abi.encodeWithSelector(IBoostedMasterWombat.withdraw.selector, _pid, _amount)
        );
        voter.safeExecute(_token, 0, abi.encodeWithSelector(IERC20.transfer.selector, msg.sender, _amount));
    }

    function pendingRewards(address _masterWombat, uint256 _pid) public view returns (Reward[] memory) {
        (, address[] memory bonusTokenAddresses,, uint256[] memory pendingBonusRewards) =
            IBoostedMasterWombat(_masterWombat).pendingTokens(_pid, address(voter));
        Reward[] memory rewards = new Reward[](bonusTokenAddresses.length);
        for (uint256 i = 0; i < bonusTokenAddresses.length; i++) {
            uint256 boostFee = bonusTokenAddresses[i] == WOM ? _calculateBoostFee(pendingBonusRewards[i]) : 0;
            rewards[i] = Reward({reward: bonusTokenAddresses[i], amount: pendingBonusRewards[i] - boostFee});
        }
        return rewards;
    }

    function getRewards(address _masterWombat, uint256 _pid) public onlyStrategy(_masterWombat, _pid) {
        Reward[] memory rewards = pendingRewards(_masterWombat, _pid);
        voter.safeExecute(_masterWombat, 0, abi.encodeWithSelector(IBoostedMasterWombat.deposit.selector, _pid, 0));
        for (uint256 i; i < rewards.length; i++) {
            uint256 reward = IERC20(rewards[i].reward).balanceOf(address(voter));

            if (rewards[i].reward == WOM) {
                uint256 reservedWom = voter.reservedWom();
                reservedWom += _calculateBoostFee(reward - reservedWom);
                reward -= reservedWom;
                if (reservedWom > minBoostAmount) {
                    _boost(reservedWom);
                    reservedWom = 0;
                }
                voter.setReservedWom(reservedWom);
            }

            voter.safeExecute(
                rewards[i].reward, 0, abi.encodeWithSelector(IERC20.transfer.selector, msg.sender, reward)
            );
        }
    }

    function _calculateBoostFee(uint256 _womAmount) internal view returns (uint256) {
        return (_womAmount * boostFeeBips) / BIPS_DIVISOR;
    }

    function _boost(uint256 _amount) internal {
        voter.safeExecute(
            address(WOM), 0, abi.encodeWithSelector(IERC20.approve.selector, address(wombatWaddle), _amount)
        );
        voter.safeExecute(
            address(wombatWaddle), 0, abi.encodeWithSelector(IWombatWaddle.mint.selector, _amount, LOCK_DAYS)
        );
    }

    function totalDeposits(address _masterWombat, uint256 _pid) external view returns (uint256) {
        (uint128 liquidity,,,) = IBoostedMasterWombat(_masterWombat).userInfo(_pid, address(voter));
        return liquidity;
    }

    function emergencyWithdraw(address _masterWombat, uint256 _pid, address _token)
        external
        onlyStrategy(_masterWombat, _pid)
    {
        voter.safeExecute(
            _masterWombat, 0, abi.encodeWithSelector(IBoostedMasterWombat.emergencyWithdraw.selector, _pid)
        );
        voter.safeExecute(
            _token,
            0,
            abi.encodeWithSelector(IERC20.transfer.selector, msg.sender, IERC20(_token).balanceOf(address(voter)))
        );
    }
}
