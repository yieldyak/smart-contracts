// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "../interfaces/ISnowballVoter.sol";
import "../interfaces/IGauge.sol";
import "../interfaces/ISnowGlobe.sol";
import "../lib/SafeERC20.sol";

library SafeProxy {
    function safeExecute(
        ISnowballVoter snowballVoter,
        address target,
        uint256 value,
        bytes memory data
    ) internal {
        (bool success, ) = snowballVoter.execute(target, value, data);
        if (!success) assert(false);
    }
}

contract SnowballProxy {
    using SafeMath for uint256;
    using SafeProxy for ISnowballVoter;
    using SafeERC20 for IERC20;

    uint256 internal constant BIPS_DIVISOR = 10000;

    uint256 public SNOB_FEE_BIPS;
    address public constant SNOB = address(0xC38f41A296A4493Ff429F1238e030924A1542e50);
    ISnowballVoter public immutable snowballVoter;
    address public immutable devAddr;

    modifier onlyDev() {
        require(msg.sender == devAddr, "SnowballProxy::onlyDev");
        _;
    }

    modifier onlyStrategy(address _stakingContract) {
        require(strategies[_stakingContract] == msg.sender, "SnowballProxy:onlyStrategy");
        _;
    }

    // stakingContract => strategies
    mapping(address => address) public strategies;

    constructor(address _snowballVoter, uint256 _snobFeeBips) {
        devAddr = msg.sender;
        SNOB_FEE_BIPS = _snobFeeBips;
        snowballVoter = ISnowballVoter(_snowballVoter);
    }

    function approveStrategy(address _stakingContract, address _strategy) external onlyDev {
        strategies[_stakingContract] = _strategy;
    }

    function setSnobFee(uint256 _snobFeeBips) external onlyDev {
        SNOB_FEE_BIPS = _snobFeeBips;
    }

    // Methods for YY Strategies
    function withdraw(
        address _stakingContract,
        address _snowGlobe,
        address _token,
        uint256 amount
    ) external onlyStrategy(_stakingContract) returns (uint256) {
        uint256 _balance = IERC20(_token).balanceOf(address(snowballVoter));
        uint256 sharesAmount = amount.mul(1e18).div(ISnowGlobe(_snowGlobe).getRatio());
        snowballVoter.safeExecute(_stakingContract, 0, abi.encodeWithSignature("withdraw(uint256)", sharesAmount));
        snowballVoter.safeExecute(_snowGlobe, 0, abi.encodeWithSignature("withdraw(uint256)", sharesAmount));
        _balance = IERC20(_token).balanceOf(address(snowballVoter)).sub(_balance);
        snowballVoter.safeExecute(
            _token,
            0,
            abi.encodeWithSignature("transfer(address,uint256)", msg.sender, _balance)
        );
        return _balance;
    }

    function withdrawAll(
        address _stakingContract,
        address _snowGlobe,
        address _token
    ) external onlyStrategy(_stakingContract) {
        snowballVoter.safeExecute(_stakingContract, 0, abi.encodeWithSignature("withdrawAll()"));
        snowballVoter.safeExecute(_snowGlobe, 0, abi.encodeWithSignature("withdrawAll()"));
        snowballVoter.safeExecute(
            _token,
            0,
            abi.encodeWithSignature(
                "transfer(address,uint256)",
                msg.sender,
                IERC20(_token).balanceOf(address(snowballVoter))
            )
        );
    }

    function deposit(
        address _stakingContract,
        address _snowGlobe,
        address _token
    ) external onlyStrategy(_stakingContract) {
        uint256 balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(address(snowballVoter), balance);

        snowballVoter.safeExecute(_token, 0, abi.encodeWithSignature("approve(address,uint256)", _snowGlobe, 0));
        snowballVoter.safeExecute(_token, 0, abi.encodeWithSignature("approve(address,uint256)", _snowGlobe, balance));
        snowballVoter.safeExecute(_snowGlobe, 0, abi.encodeWithSignature("deposit(uint256)", balance));

        uint256 snowballSharesAmount = ISnowGlobe(_snowGlobe).balanceOf(address(snowballVoter));
        snowballVoter.safeExecute(
            _snowGlobe,
            0,
            abi.encodeWithSignature("approve(address,uint256)", _stakingContract, 0)
        );
        snowballVoter.safeExecute(
            _snowGlobe,
            0,
            abi.encodeWithSignature("approve(address,uint256)", _stakingContract, snowballSharesAmount)
        );
        snowballVoter.safeExecute(
            _stakingContract,
            0,
            abi.encodeWithSignature("deposit(uint256)", snowballSharesAmount)
        );
    }

    function balanceOf(address _stakingContract, address _snowGlobe) public view returns (uint256) {
        uint256 ratio = ISnowGlobe(_snowGlobe).getRatio();
        return IGauge(_stakingContract).balanceOf(address(snowballVoter)).mul(ratio).div(1e18);
    }

    function checkReward(address _stakingContract) public view returns (uint256) {
        uint256 pendingReward = IGauge(_stakingContract).earned(address(snowballVoter));
        uint256 snobFee = pendingReward.mul(SNOB_FEE_BIPS).div(BIPS_DIVISOR);
        return pendingReward.sub(snobFee);
    }

    function claimReward(address _stakingContract) external onlyStrategy(_stakingContract) {
        uint256 pendingReward = IGauge(_stakingContract).earned(address(snowballVoter));
        uint256 snobFee = pendingReward.mul(SNOB_FEE_BIPS).div(BIPS_DIVISOR);
        uint256 transferAmount = pendingReward.sub(snobFee);
        snowballVoter.safeExecute(_stakingContract, 0, abi.encodeWithSignature("getReward()"));
        snowballVoter.safeExecute(
            SNOB,
            0,
            abi.encodeWithSignature("transfer(address,uint256)", msg.sender, transferAmount)
        );
    }
}
