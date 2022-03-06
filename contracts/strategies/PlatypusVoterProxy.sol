// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;
pragma experimental ABIEncoderV2;

import "../interfaces/IPlatypusVoter.sol";
import "../interfaces/IMasterPlatypus.sol";
import "../interfaces/IPlatypusPool.sol";
import "../interfaces/IPlatypusAsset.sol";
import "../interfaces/IPlatypusStrategy.sol";
import "../interfaces/IPlatypusVoterProxy.sol";
import "../lib/SafeERC20.sol";

library SafeProxy {
    function safeExecute(
        IPlatypusVoter platypusVoter,
        address target,
        uint256 value,
        bytes memory data
    ) internal returns (bytes memory) {
        (bool success, bytes memory returnValue) = platypusVoter.execute(target, value, data);
        if (!success) revert("PlatypusVoterProxy::safeExecute failed");
        return returnValue;
    }
}

/**
 * @notice PlatypusVoterProxy is an upgradable contract.
 * Strategies interact with PlatypusVoterProxy and
 * PlatypusVoterProxy interacts with PlatypusVoter.
 * @dev For accounting reasons, there is one approved
 * strategy per Masterchef PID. In case of upgrade,
 * use a new proxy.
 */
contract PlatypusVoterProxy is IPlatypusVoterProxy {
    using SafeMath for uint256;
    using SafeProxy for IPlatypusVoter;
    using SafeERC20 for IERC20;

    struct FeeSettings {
        uint256 stakerFeeBips;
        uint256 boosterFeeBips;
        address stakerFeeReceiver;
        address boosterFeeReceiver;
    }

    uint256 internal constant BIPS_DIVISOR = 10000;

    uint256 public boosterFee;
    uint256 public stakerFee;
    address public stakerFeeReceiver;
    address public boosterFeeReceiver;
    address public constant PTP = address(0x22d4002028f537599bE9f666d1c4Fa138522f9c8);
    IPlatypusVoter public immutable override platypusVoter;
    address public devAddr;

    mapping(uint256 => address) private approvedStrategies;

    modifier onlyDev() {
        require(msg.sender == devAddr, "PlatypusVoterProxy::onlyDev");
        _;
    }

    modifier onlyStrategy(uint256 pid) {
        require(approvedStrategies[pid] == msg.sender, "PlatypusVoterProxy::onlyStrategy");
        _;
    }

    constructor(
        address _platypusVoter,
        address _devAddr,
        FeeSettings memory _feeSettings
    ) {
        devAddr = _devAddr;
        boosterFee = _feeSettings.boosterFeeBips;
        stakerFee = _feeSettings.stakerFeeBips;
        stakerFeeReceiver = _feeSettings.stakerFeeReceiver;
        boosterFeeReceiver = _feeSettings.boosterFeeReceiver;
        platypusVoter = IPlatypusVoter(_platypusVoter);
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
     * @dev Can only be set once per PID (reported by the strategy)
     * @param _strategy address
     */
    function approveStrategy(address _strategy) external override onlyDev {
        uint256 pid = IPlatypusStrategy(_strategy).PID();
        require(approvedStrategies[pid] == address(0), "PlatypusVoterProxy::Strategy for PID already added");
        approvedStrategies[pid] = _strategy;
    }

    /**
     * @notice Update booster fee
     * @dev Restricted to devAddr
     * @param _boosterFeeBips new fee in bips (1% = 100 bips)
     */
    function setBoosterFee(uint256 _boosterFeeBips) external onlyDev {
        boosterFee = _boosterFeeBips;
    }

    /**
     * @notice Update staker fee
     * @dev Restricted to devAddr
     * @param _stakerFeeBips new fee in bips (1% = 100 bips)
     */
    function setStakerFee(uint256 _stakerFeeBips) external onlyDev {
        stakerFee = _stakerFeeBips;
    }

    /**
     * @notice Update booster fee receiver
     * @dev Restricted to devAddr
     * @param _boosterFeeReceiver address
     */
    function setBoosterFeeReceiver(address _boosterFeeReceiver) external onlyDev {
        boosterFeeReceiver = _boosterFeeReceiver;
    }

    /**
     * @notice Update staker fee receiver
     * @dev Restricted to devAddr
     * @param _stakerFeeReceiver address
     */
    function setStakerFeeReceiver(address _stakerFeeReceiver) external onlyDev {
        stakerFeeReceiver = _stakerFeeReceiver;
    }

    /**
     * @notice Deposit function
     * @dev Restricted to strategy with _pid
     * @param _pid PID
     * @param _stakingContract Platypus Masterchef
     * @param _pool Platypus pool
     * @param _token Deposit asset
     * @param _asset Platypus asset
     * @param _amount deposit amount
     * @param _depositFee deposit fee
     */
    function deposit(
        uint256 _pid,
        address _stakingContract,
        address _pool,
        address _token,
        address _asset,
        uint256 _amount,
        uint256 _depositFee
    ) external override onlyStrategy(_pid) {
        uint256 liquidity = _depositTokenToAsset(_asset, _amount, _depositFee);
        IERC20(_token).safeApprove(_pool, _amount);
        IPlatypusPool(_pool).deposit(address(_token), _amount, address(platypusVoter), type(uint256).max);
        platypusVoter.safeExecute(
            _asset,
            0,
            abi.encodeWithSignature("approve(address,uint256)", _stakingContract, liquidity)
        );
        platypusVoter.safeExecute(
            _stakingContract,
            0,
            abi.encodeWithSignature("deposit(uint256,uint256)", _pid, liquidity)
        );
        platypusVoter.safeExecute(_asset, 0, abi.encodeWithSignature("approve(address,uint256)", _stakingContract, 0));
    }

    /**
     * @notice Conversion for deposit token to Platypus asset
     * @return liquidity amount of LP tokens
     */
    function _depositTokenToAsset(
        address _asset,
        uint256 _amount,
        uint256 _depositFee
    ) private view returns (uint256 liquidity) {
        if (IPlatypusAsset(_asset).liability() == 0) {
            liquidity = _amount.sub(_depositFee);
        } else {
            liquidity = ((_amount.sub(_depositFee)).mul(IPlatypusAsset(_asset).totalSupply())).div(
                IPlatypusAsset(_asset).liability()
            );
        }
    }

    /**
     * @notice Calculation of reinvest fee (boost + staking)
     * @return reinvest fee
     */
    function reinvestFeeBips() external view override returns (uint256) {
        uint256 boostFee = 0;
        if (boosterFee > 0 && boosterFeeReceiver > address(0) && platypusVoter.depositsEnabled()) {
            boostFee = boosterFee;
        }

        uint256 stakingFee = 0;
        if (stakerFee > 0 && stakerFeeReceiver > address(0)) {
            stakingFee = stakerFee;
        }
        return boostFee.add(stakingFee);
    }

    /**
     * @notice Calculation of withdraw fee
     * @param _pool Platypus pool
     * @param _token Withdraw token
     * @param _amount Withdraw amount, in _token
     * @return fee Withdraw fee
     */
    function _calculateWithdrawFee(
        address _pool,
        address _token,
        uint256 _amount
    ) private view returns (uint256 fee) {
        (, fee, ) = IPlatypusPool(_pool).quotePotentialWithdraw(_token, _amount);
    }

    /**
     * @notice Conversion for handling withdraw
     * @param _pid PID
     * @param _stakingContract Platypus Masterchef
     * @param _amount withdraw amount in deposit asset
     * @return liquidity LP tokens
     */
    function _depositTokenToAssetForWithdrawal(
        uint256 _pid,
        address _stakingContract,
        uint256 _amount
    ) private view returns (uint256) {
        uint256 totalDeposits = _poolBalance(_stakingContract, _pid);
        (uint256 balance, , ) = IMasterPlatypus(_stakingContract).userInfo(_pid, address(platypusVoter));
        return _amount.mul(balance).div(totalDeposits);
    }

    /**
     * @notice Withdraw function
     * @dev Restricted to strategy with _pid
     * @param _pid PID
     * @param _stakingContract Platypus Masterchef
     * @param _pool Platypus pool
     * @param _token Deposit asset
     * @param _asset Platypus asset
     * @param _maxSlippage max slippage in bips
     * @param _amount withdraw amount
     * @return amount withdrawn, in _token
     */
    function withdraw(
        uint256 _pid,
        address _stakingContract,
        address _pool,
        address _token,
        address _asset,
        uint256 _maxSlippage,
        uint256 _amount
    ) external override onlyStrategy(_pid) returns (uint256) {
        uint256 liquidity = _depositTokenToAssetForWithdrawal(_pid, _stakingContract, _amount);
        platypusVoter.safeExecute(
            _stakingContract,
            0,
            abi.encodeWithSignature("withdraw(uint256,uint256)", _pid, liquidity)
        );
        platypusVoter.safeExecute(_asset, 0, abi.encodeWithSignature("approve(address,uint256)", _pool, liquidity));
        uint256 minimumReceive = liquidity.sub(_calculateWithdrawFee(_pool, _token, liquidity));
        uint256 slippage = minimumReceive.mul(_maxSlippage).div(BIPS_DIVISOR);
        minimumReceive = minimumReceive.sub(slippage);
        bytes memory result = platypusVoter.safeExecute(
            _pool,
            0,
            abi.encodeWithSignature(
                "withdraw(address,uint256,uint256,address,uint256)",
                _token,
                liquidity,
                minimumReceive,
                address(this),
                type(uint256).max
            )
        );
        platypusVoter.safeExecute(_asset, 0, abi.encodeWithSignature("approve(address,uint256)", _pool, 0));
        uint256 amount = toUint256(result, 0);
        IERC20(_token).safeTransfer(msg.sender, amount);
        return amount;
    }

    /**
     * @notice Emergency withdraw function
     * @dev Restricted to strategy with _pid
     * @param _pid PID
     * @param _stakingContract Platypus Masterchef
     * @param _pool Platypus pool
     * @param _token Deposit asset
     * @param _asset Platypus asset
     */
    function emergencyWithdraw(
        uint256 _pid,
        address _stakingContract,
        address _pool,
        address _token,
        address _asset
    ) external override onlyStrategy(_pid) {
        platypusVoter.safeExecute(_stakingContract, 0, abi.encodeWithSignature("emergencyWithdraw(uint256)", _pid));
        uint256 balance = IERC20(_asset).balanceOf(address(platypusVoter));
        (uint256 expectedAmount, , ) = IPlatypusPool(_pool).quotePotentialWithdraw(_token, balance);
        platypusVoter.safeExecute(_asset, 0, abi.encodeWithSignature("approve(address,uint256)", _pool, balance));
        platypusVoter.safeExecute(
            _pool,
            0,
            abi.encodeWithSignature(
                "withdraw(address,uint256,uint256,address,uint256)",
                _token,
                balance,
                expectedAmount,
                msg.sender,
                type(uint256).max
            )
        );
        platypusVoter.safeExecute(_asset, 0, abi.encodeWithSignature("approve(address,uint256)", _stakingContract, 0));
        platypusVoter.safeExecute(_token, 0, abi.encodeWithSignature("approve(address,uint256)", _pool, 0));
    }

    /**
     * @notice Pending rewards matching interface for PlatypusStrategy
     * @param _stakingContract Platypus Masterchef
     * @param _pid PID
     * @return pendingPtp
     * @return pendingBonusToken
     * @return bonusTokenAddress
     */
    function pendingRewards(address _stakingContract, uint256 _pid)
        external
        view
        override
        returns (
            uint256,
            uint256,
            address
        )
    {
        (uint256 pendingPtp, address bonusTokenAddress, , uint256 pendingBonusToken) = IMasterPlatypus(_stakingContract)
            .pendingTokens(_pid, address(platypusVoter));

        return (pendingPtp, pendingBonusToken, bonusTokenAddress);
    }

    /**
     * @notice Pool balance
     * @param _stakingContract Platypus Masterchef
     * @param _pid PID
     * @return balance in depositToken
     */
    function poolBalance(address _stakingContract, uint256 _pid) external view override returns (uint256 balance) {
        return _poolBalance(_stakingContract, _pid);
    }

    function _poolBalance(address _stakingContract, uint256 _pid) internal view returns (uint256 balance) {
        (uint256 assetBalance, , ) = IMasterPlatypus(_stakingContract).userInfo(_pid, address(platypusVoter));
        if (assetBalance == 0) return 0;
        (address asset, , , , , , ) = IMasterPlatypus(_stakingContract).poolInfo(_pid);
        return (IPlatypusAsset(asset).liability() * assetBalance) / IPlatypusAsset(asset).totalSupply();
    }

    /**
     * @notice Claim and distribute PTP rewards
     * @dev Restricted to strategy with _pid
     * @param _stakingContract Platypus Masterchef
     * @param _pid PID
     */
    function claimReward(address _stakingContract, uint256 _pid) external override onlyStrategy(_pid) {
        (uint256 pendingPtp, address bonusTokenAddress, , uint256 pendingBonusToken) = IMasterPlatypus(_stakingContract)
            .pendingTokens(_pid, address(platypusVoter));

        uint256 ptpDust = IERC20(PTP).balanceOf(address(platypusVoter));
        pendingPtp = pendingPtp.add(ptpDust);

        if (bonusTokenAddress > address(0)) {
            uint256 bonusTokenDust = IERC20(bonusTokenAddress).balanceOf(address(platypusVoter));
            pendingBonusToken = pendingBonusToken.add(bonusTokenDust);
        }

        uint256[] memory pids = new uint256[](1);
        pids[0] = _pid;
        platypusVoter.safeExecute(_stakingContract, 0, abi.encodeWithSignature("multiClaim(uint256[])", pids));

        uint256 boostFee = 0;
        if (boosterFee > 0 && boosterFeeReceiver > address(0) && platypusVoter.depositsEnabled()) {
            boostFee = pendingPtp.mul(boosterFee).div(BIPS_DIVISOR);
            platypusVoter.depositFromBalance(boostFee);
            IERC20(address(platypusVoter)).safeTransfer(boosterFeeReceiver, boostFee);
        }

        uint256 stakingFee = 0;
        if (stakerFee > 0 && stakerFeeReceiver > address(0)) {
            stakingFee = pendingPtp.mul(stakerFee).div(BIPS_DIVISOR);
            platypusVoter.safeExecute(
                PTP,
                0,
                abi.encodeWithSignature("transfer(address,uint256)", stakerFeeReceiver, stakingFee)
            );
        }

        uint256 reward = pendingPtp.sub(boostFee).sub(stakingFee);
        platypusVoter.safeExecute(PTP, 0, abi.encodeWithSignature("transfer(address,uint256)", msg.sender, reward));

        if (bonusTokenAddress > address(0)) {
            platypusVoter.wrapAvaxBalance();
            platypusVoter.safeExecute(
                bonusTokenAddress,
                0,
                abi.encodeWithSignature("transfer(address,uint256)", msg.sender, pendingBonusToken)
            );
        }

        if (platypusVoter.vePTPBalance() > 0) {
            platypusVoter.claimVePTP();
        }
    }

    function toUint256(bytes memory _bytes, uint256 _start) internal pure returns (uint256) {
        require(_bytes.length >= _start.add(32), "toUint256_outOfBounds");
        uint256 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x20), _start))
        }

        return tempUint;
    }
}
