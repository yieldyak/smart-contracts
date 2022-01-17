// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

import "../interfaces/IPlatypusVoter.sol";
import "../interfaces/IMasterPlatypus.sol";
import "../interfaces/IPlatypusPool.sol";
import "../lib/SafeERC20.sol";

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

    uint256 internal constant BIPS_DIVISOR = 10000;

    uint256 public ptpFee;
    bool public staking;
    address public constant PTP = address(0x22d4002028f537599bE9f666d1c4Fa138522f9c8);
    IPlatypusVoter public immutable platypusVoter;
    address public immutable devAddr;

    modifier onlyDev() {
        require(msg.sender == devAddr, "PlatypusVoterProxy::onlyDev");
        _;
    }

    modifier onlyStrategy(address _asset) {
        require(strategies[_asset] == msg.sender, "PlatypusVoterProxy:onlyStrategy");
        _;
    }

    // asset => strategies
    mapping(address => address) public strategies;

    constructor(
        address _platypusVoter,
        uint256 _ptpFeeBips,
        bool _staking,
        address _devAddr
    ) {
        devAddr = _devAddr;
        ptpFee = _ptpFeeBips;
        staking = _staking;
        platypusVoter = IPlatypusVoter(_platypusVoter);
    }

    function approveStrategy(address _asset, address _strategy) external onlyDev {
        strategies[_asset] = _strategy;
    }

    function setPTPFee(uint256 _ptpFeeBips) external onlyDev {
        ptpFee = _ptpFeeBips;
    }

    function setStaking(bool _staking) external onlyDev {
        staking = _staking;
    }

    function deposit(
        uint256 _pid,
        address _stakingContract,
        address _pool,
        address _token,
        address _asset,
        uint256 _amount
    ) external onlyStrategy(_asset) {
        IERC20(_token).safeApprove(_pool, _amount);
        uint256 liquidity = IPlatypusPool(_pool).deposit(
            address(_token),
            _amount,
            address(platypusVoter),
            type(uint256).max
        );
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

    function toUint256(bytes memory _bytes, uint256 _start) internal pure returns (uint256) {
        require(_bytes.length >= _start + 32, "toUint256_outOfBounds");
        uint256 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x20), _start))
        }

        return tempUint;
    }

    function _calculateWithdrawFee(
        address _pool,
        address _token,
        uint256 _amount
    ) internal view returns (uint256 fee) {
        (, fee, ) = IPlatypusPool(_pool).quotePotentialWithdraw(_token, _amount);
    }

    function withdraw(
        uint256 _pid,
        address _stakingContract,
        address _pool,
        address _token,
        address _asset,
        uint256 _maxSlippage,
        uint256 _amount
    ) external onlyStrategy(_asset) returns (uint256) {
        platypusVoter.safeExecute(
            _stakingContract,
            0,
            abi.encodeWithSignature("withdraw(uint256,uint256)", _pid, _amount)
        );
        platypusVoter.safeExecute(_asset, 0, abi.encodeWithSignature("approve(address,uint256)", _pool, _amount));
        uint256 withdrawAmount = _amount.sub(_calculateWithdrawFee(_pool, _token, _amount));
        uint256 slippage = withdrawAmount.mul(_maxSlippage).div(BIPS_DIVISOR);
        withdrawAmount = withdrawAmount.sub(slippage);
        bytes memory result = platypusVoter.safeExecute(
            _pool,
            0,
            abi.encodeWithSignature(
                "withdraw(address,uint256,uint256,address,uint256)",
                _token,
                _amount,
                withdrawAmount,
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
    ) external onlyStrategy(_asset) {
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

    function claimReward(
        address _stakingContract,
        uint256 _pid,
        address _asset
    ) external onlyStrategy(_asset) {
        (uint256 pendingPtp, address bonusTokenAddress, , uint256 pendingBonusToken) = IMasterPlatypus(_stakingContract)
            .pendingTokens(_pid, address(platypusVoter));

        uint256[] memory pids = new uint256[](1);
        pids[0] = _pid;

        platypusVoter.safeExecute(_stakingContract, 0, abi.encodeWithSignature("multiClaim(uint256[])", pids));

        uint256 boostFee = pendingPtp.mul(ptpFee).div(BIPS_DIVISOR);
        uint256 reward = pendingPtp.sub(boostFee);

        platypusVoter.safeExecute(PTP, 0, abi.encodeWithSignature("transfer(address,uint256)", msg.sender, reward));

        if (staking) {
            platypusVoter.increaseStake(boostFee);
        }

        if (bonusTokenAddress > address(0)) {
            platypusVoter.wrapAvaxBalance();
            platypusVoter.safeExecute(
                bonusTokenAddress,
                0,
                abi.encodeWithSignature("transfer(address,uint256)", msg.sender, pendingBonusToken)
            );
        }
    }
}
