// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;
pragma experimental ABIEncoderV2;

import "../interfaces/IPlatypusVoter.sol";
import "../interfaces/IMasterPlatypus.sol";
import "../interfaces/IPlatypusPool.sol";
import "../interfaces/IPlatypusAsset.sol";
import "../interfaces/IPlatypusStrategy.sol";
import "../lib/SafeERC20.sol";
import "../lib/EnumerableSet.sol";

library SafeProxy {
    function safeExecute(
        IPlatypusVoter platypusVoter,
        address target,
        uint256 value,
        bytes memory data
    ) internal returns (bytes memory) {
        (bool success, bytes memory returnValue) = platypusVoter.execute(target, value, data);
        if (!success) assert(false);
        return returnValue;
    }
}

contract PlatypusVoterProxy {
    using SafeMath for uint256;
    using SafeProxy for IPlatypusVoter;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

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
    IPlatypusVoter public immutable platypusVoter;
    address public immutable devAddr;

    mapping(uint256 => address) private pidToStrategy;
    EnumerableSet.AddressSet private approvedStrategies;

    modifier onlyDev() {
        require(msg.sender == devAddr, "PlatypusVoterProxy::onlyDev");
        _;
    }

    modifier onlyStrategy() {
        require(approvedStrategies.contains(msg.sender), "PlatypusVoterProxy::onlyStrategy");
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

    function approveStrategy(address _strategy) external onlyDev {
        uint256 pid = IPlatypusStrategy(_strategy).PID();
        require(pidToStrategy[pid] == address(0), "PlatypusVoterProxy::Strategy for PID already added");
        pidToStrategy[pid] = _strategy;
        approvedStrategies.add(_strategy);
    }

    function isApprovedStrategy(address _strategy) external view returns (bool) {
        return approvedStrategies.contains(_strategy);
    }

    function setBoosterFee(uint256 _boosterFeeBips) external onlyDev {
        boosterFee = _boosterFeeBips;
    }

    function setStakerFee(uint256 _stakerFeeBips) external onlyDev {
        stakerFee = _stakerFeeBips;
    }

    function setBoosterFeeReceiver(address _boosterFeeReceiver) external onlyDev {
        boosterFeeReceiver = _boosterFeeReceiver;
    }

    function setStakerFeeReceiver(address _stakerFeeReceiver) external onlyDev {
        stakerFeeReceiver = _stakerFeeReceiver;
    }

    function deposit(
        uint256 _pid,
        address _stakingContract,
        address _pool,
        address _token,
        address _asset,
        uint256 _amount,
        uint256 _depositFee
    ) external onlyStrategy {
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
    }

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

    function reinvestFeeBips() external returns (uint256) {
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

    function _calculateWithdrawFee(
        address _pool,
        address _token,
        uint256 _amount
    ) private view returns (uint256 fee) {
        (, fee, ) = IPlatypusPool(_pool).quotePotentialWithdraw(_token, _amount);
    }

    function _depositTokenToAssetForWithdrawal(
        uint256 _pid,
        address _stakingContract,
        uint256 _amount,
        uint256 _totalDeposits
    ) private view returns (uint256) {
        (uint256 balance, , ) = IMasterPlatypus(_stakingContract).userInfo(_pid, address(platypusVoter));
        return _amount.mul(balance).div(_totalDeposits);
    }

    function withdraw(
        uint256 _pid,
        address _stakingContract,
        address _pool,
        address _token,
        address _asset,
        uint256 _maxSlippage,
        uint256 _amount,
        uint256 _totalDeposits
    ) external onlyStrategy returns (uint256) {
        uint256 liquidity = _depositTokenToAssetForWithdrawal(_pid, _stakingContract, _amount, _totalDeposits);
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
        uint256 amount = toUint256(result, 0);
        IERC20(_token).safeTransfer(msg.sender, amount);
        return amount;
    }

    function emergencyWithdraw(
        uint256 _pid,
        address _stakingContract,
        address _pool,
        address _token,
        address _asset
    ) external onlyStrategy {
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

    function claimReward(address _stakingContract, uint256 _pid) external onlyStrategy {
        (uint256 pendingPtp, address bonusTokenAddress, , uint256 pendingBonusToken) = IMasterPlatypus(_stakingContract)
            .pendingTokens(_pid, address(platypusVoter));

        uint256[] memory pids = new uint256[](1);
        pids[0] = _pid;

        platypusVoter.safeExecute(_stakingContract, 0, abi.encodeWithSignature("multiClaim(uint256[])", pids));

        uint256 boostFee = 0;
        if (boosterFee > 0 && boosterFeeReceiver > address(0) && platypusVoter.depositsEnabled()) {
            boostFee = pendingPtp.mul(boosterFee).div(BIPS_DIVISOR);
            platypusVoter.depositFromBalance(boostFee);
            IERC20(address(platypusVoter)).safeTransfer(boosterFeeReceiver, boostFee);
        } else {
            if (platypusVoter.vePTPBalance() > 0) {
                platypusVoter.claimVePTP();
            }
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
    }

    function toUint256(bytes memory _bytes, uint256 _start) internal pure returns (uint256) {
        require(_bytes.length >= _start + 32, "toUint256_outOfBounds");
        uint256 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x20), _start))
        }

        return tempUint;
    }
}
