// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../interfaces/IProxy.sol";
import "../interfaces/IGauge.sol";
import "../interfaces/ISnowGlobe.sol";
import "../lib/Ownable.sol";

import "hardhat/console.sol";


library SafeProxy {
    function safeExecute(
        IProxy proxy,
        address to,
        uint256 value,
        bytes memory data
    ) internal {
        (bool success, ) = proxy.execute(to, value, data);
        if (!success) assert(false);
    }
}

contract SnowballProxy is Ownable {
    using SafeMath for uint256;
    using SafeProxy for IProxy;
    using SafeERC20 for IERC20;

    IProxy public immutable proxy;
    address constant public snob = address(0xC38f41A296A4493Ff429F1238e030924A1542e50);
    address public constant stakingContract = address(0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB);
    
    // stakingContract => strategies
    mapping(address => address) public strategies;

    uint256 lastTimeCursor;

    constructor(address _proxy) {
        proxy = IProxy(_proxy);
    }

    function approveStrategy(address _stakingContract, address _strategy) external onlyOwner {
        strategies[_stakingContract] = _strategy;
    }

    function revokeStrategy(address _stakingContract) external onlyOwner {
        strategies[_stakingContract] = address(0);
    }

    function lock() external {
        uint256 amount = IERC20(snob).balanceOf(address(proxy));
        if (amount > 0) proxy.increaseAmount(amount);
    }

    function vote(address _stakingContract, uint256 _amount) external onlyOwner {
        // TODO add voting capabilities
    }

    function withdraw(
        address _stakingContract,
        address _snowGlobe,
        address _token,
        uint amount
    ) public returns (uint256) {
        require(strategies[_stakingContract] == msg.sender, "!strategy");
        uint256 _balance = IERC20(_token).balanceOf(address(proxy));
        uint sharesAmount = amount.mul(1e18).div(ISnowGlobe(_snowGlobe).getRatio());
        uint ratio = ISnowGlobe(_snowGlobe).getRatio();
        proxy.safeExecute(_stakingContract, 0, abi.encodeWithSignature("withdraw(uint256)", sharesAmount));
        proxy.safeExecute(_snowGlobe, 0, abi.encodeWithSignature("withdraw(uint256)", sharesAmount));
        _balance = IERC20(_token).balanceOf(address(proxy)).sub(_balance);
        proxy.safeExecute(_token, 0, abi.encodeWithSignature("transfer(address,uint256)", msg.sender, _balance));
        return _balance;
    }

    function withdrawAll(address _stakingContract, address _snowGlobe, address _token) external {
        require(strategies[_stakingContract] == msg.sender, "!strategy");
        proxy.safeExecute(_stakingContract, 0, abi.encodeWithSignature("withdrawAll()"));
        proxy.safeExecute(_snowGlobe, 0, abi.encodeWithSignature("withdrawAll()"));
        proxy.safeExecute(_token, 0, abi.encodeWithSignature("transfer(address,uint256)", msg.sender, IERC20(_token).balanceOf(address(proxy))));
    }

    function deposit(address _stakingContract, address _snowGlobe, address _token) external returns (uint256) {
        require(strategies[_stakingContract] == msg.sender, "!strategy");
        uint256 _balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(address(proxy), _balance);
        _balance = IERC20(_token).balanceOf(address(proxy));

        proxy.safeExecute(_token, 0, abi.encodeWithSignature("approve(address,uint256)", _snowGlobe, 0));
        proxy.safeExecute(_token, 0, abi.encodeWithSignature("approve(address,uint256)", _snowGlobe, _balance));
        uint ratio = ISnowGlobe(_snowGlobe).getRatio();
        proxy.safeExecute(_snowGlobe, 0, abi.encodeWithSignature("deposit(uint256)", _balance));
        uint snowballSharesAmount = ISnowGlobe(_snowGlobe).balanceOf(address(proxy));
        uint lpAmountDeposited = snowballSharesAmount.mul(ratio).div(1e18);
        proxy.safeExecute(_snowGlobe, 0, abi.encodeWithSignature("approve(address,uint256)", _stakingContract, 0));
        proxy.safeExecute(_snowGlobe, 0, abi.encodeWithSignature("approve(address,uint256)", _stakingContract, snowballSharesAmount));
        proxy.safeExecute(_stakingContract, 0, abi.encodeWithSignature("deposit(uint256)", snowballSharesAmount));
        return lpAmountDeposited;
    }

    function balanceOf(address _stakingContract) public view returns (uint256) {
        return IERC20(_stakingContract).balanceOf(address(proxy));
    }

    function checkReward(address _stakingContract) public view returns (uint) {
        return IGauge(_stakingContract).earned(address(proxy));
    }

    function claimRewards(address _stakingContract) external {
        require(strategies[_stakingContract] == msg.sender, "!strategy");
        proxy.safeExecute(_stakingContract, 0, abi.encodeWithSignature("getReward()"));
        proxy.safeExecute(snob, 0, abi.encodeWithSignature("transfer(address,uint256)", msg.sender, IERC20(snob).balanceOf(address(proxy))));
    }
}