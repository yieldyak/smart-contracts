// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../../lib/SafeERC20.sol";
import "../../../lib/AccessControl.sol";
import "./interfaces/IFlairVoter.sol";
import "./interfaces/IFlairGaugeVoter.sol";
import "./interfaces/IGauge.sol";
import "./interfaces/IBribe.sol";

library SafeProxy {
    function safeExecute(IFlairVoter voter, address target, uint256 value, bytes memory data)
        internal
        returns (bytes memory)
    {
        (bool success, bytes memory returnValue) = voter.execute(target, value, data);
        if (!success) revert("FlairVoterProxy::safeExecute failed");
        return returnValue;
    }
}

/**
 * @notice FlairVoterProxy is an upgradable contract.
 * It collects an additional fee from Flair strategies to accumulate veFLDX
 */
contract FlairVoterProxy is AccessControl {
    using SafeProxy for IFlairVoter;
    using SafeERC20 for IERC20;

    struct Reward {
        address reward;
        uint256 amount;
    }

    uint256 internal constant BIPS_DIVISOR = 10000;
    uint256 internal constant MAX_BOOST_FEE_BIPS = 1000;
    address internal constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    address internal constant FLDX = 0x107D2b7C619202D994a4d044c762Dd6F8e0c5326;
    address internal constant GAUGE_VOTER = 0x3a0bA70ca11617F3Ec06c0d99185095477AFF4d4;

    IFlairVoter public immutable voter;

    mapping(address => uint256) public boostFeeBips;
    bool public paused = false;

    // staking contract => strategy
    mapping(address => address) public approvedStrategies;

    /// @notice Role to vote for gauge voting
    bytes32 public constant VOTING_ROLE = keccak256("VOTING_ROLE");

    /// @notice Role to approve strategies
    bytes32 public constant APPROVE_ROLE = keccak256("APPROVE_ROLE");

    /// @notice Role to manage booster fees per strategy
    bytes32 public constant FEE_SETTER_ROLE = keccak256("FEE_SETTER_ROLE");

    modifier onlyStrategy(address _gauge) {
        require(approvedStrategies[_gauge] == msg.sender, "FlairVoterProxy::onlyStrategy");
        _;
    }

    event Paused(bool paused);
    event BoostFeeUpdated(address strategy, uint256 oldValue, uint256 newValue);
    event Sweep(address indexed sweeper, address indexed token, uint256 amount);

    constructor(address _team, address _deployer, address _voting, address _voter) {
        _setupRole(FEE_SETTER_ROLE, _deployer);
        _setupRole(FEE_SETTER_ROLE, _team);
        _setupRole(APPROVE_ROLE, _deployer);
        _setupRole(APPROVE_ROLE, _team);
        _setupRole(VOTING_ROLE, _voting);
        voter = IFlairVoter(_voter);
    }

    function approveStrategy(address _stakingContract, address _strategy) public {
        require(hasRole(APPROVE_ROLE, msg.sender), "FlairVoterProxy::auth");
        require(approvedStrategies[_stakingContract] == address(0), "FlairVoterProxy::Strategy for gauge already added");
        approvedStrategies[_stakingContract] = _strategy;
    }

    function updateBoostFee(address _strategy, uint256 _boostFeeBips) public {
        require(hasRole(FEE_SETTER_ROLE, msg.sender), "FlairVoterProxy::auth");
        require(_boostFeeBips <= MAX_BOOST_FEE_BIPS, "FlairVoterProxy::Boost fee too high");
        uint256 oldValue = boostFeeBips[_strategy];
        boostFeeBips[_strategy] = _boostFeeBips;
        emit BoostFeeUpdated(_strategy, oldValue, _boostFeeBips);
    }

    function vote(address[] calldata _poolVote, int256[] calldata _weights) external {
        require(hasRole(VOTING_ROLE, msg.sender), "FlairVoterProxy::auth");
        voter.safeExecute(
            GAUGE_VOTER, 0, abi.encodeWithSelector(IFlairGaugeVoter.vote.selector, voter.tokenId(), _poolVote, _weights)
        );
    }

    function deposit(address _gauge, address _token, uint256 _amount) external onlyStrategy(_gauge) {
        voter.safeExecute(_token, 0, abi.encodeWithSelector(IERC20.approve.selector, _gauge, _amount));
        voter.safeExecute(_gauge, 0, abi.encodeWithSelector(IGauge.deposit.selector, _amount, voter.tokenId()));
    }

    function withdraw(address _gauge, address _token, uint256 _amount) external onlyStrategy(_gauge) {
        voter.safeExecute(_gauge, 0, abi.encodeWithSelector(IGauge.withdraw.selector, _amount));
        voter.safeExecute(_token, 0, abi.encodeWithSelector(IERC20.transfer.selector, msg.sender, _amount));
    }

    function pendingRewards(address _gauge, address[] memory _tokens, bool _claimBribes)
        external
        view
        returns (Reward[] memory)
    {
        uint256 count = _tokens.length;
        Reward[] memory rewards = new Reward[](count);
        uint256 boostBips = boostFeeBips[msg.sender];
        address bribe = IGauge(_gauge).bribe();
        for (uint256 i = 0; i < count; i++) {
            address token = _tokens[i];
            uint256 amount = IGauge(_gauge).earned(token, address(voter));
            if (_claimBribes) {
                amount += IGauge(bribe).earned(token, address(voter));
            }
            uint256 boostFee;
            if (boostBips > 0 && _tokens[i] == FLDX) {
                boostFee = (amount * boostBips) / BIPS_DIVISOR;
            }
            rewards[i] = Reward({reward: token, amount: amount - boostFee});
        }
        return rewards;
    }

    function getRewards(address _gauge, address[] memory _tokens, bool _claimBribes) external onlyStrategy(_gauge) {
        voter.safeExecute(_gauge, 0, abi.encodeWithSelector(IGauge.getReward.selector, address(voter), _tokens));
        uint256 boostBips = boostFeeBips[msg.sender];
        for (uint256 i; i < _tokens.length; i++) {
            uint256 amount = IERC20(_tokens[i]).balanceOf(address(voter));
            uint256 boostFee;
            if (boostBips > 0 && _tokens[i] == FLDX) {
                boostFee = (amount * boostBips) / BIPS_DIVISOR;
                voter.depositFromBalance(boostFee);
            }
            voter.safeExecute(
                _tokens[i], 0, abi.encodeWithSelector(IERC20.transfer.selector, msg.sender, amount - boostFee)
            );
        }
        if (_claimBribes) {
            address bribe = IGauge(_gauge).bribe();
            uint256 rewardTokensLength = IBribe(bribe).rewardTokensLength();
            address[] memory tokens = new address[](rewardTokensLength);
            for (uint256 i; i < rewardTokensLength; i++) {
                tokens[i] = IBribe(bribe).rewardTokens(i);
            }
            voter.safeExecute(bribe, 0, abi.encodeWithSelector(IBribe.getReward.selector, voter.tokenId(), tokens));
            for (uint256 i = 0; i < tokens.length; i++) {
                uint256 amount = IERC20(tokens[i]).balanceOf(address(voter));
                if (amount > 0) {
                    voter.safeExecute(
                        tokens[i], 0, abi.encodeWithSelector(IERC20.transfer.selector, msg.sender, amount)
                    );
                }
            }
        }
    }

    function totalDeposits(address _gauge) external view returns (uint256) {
        return IGauge(_gauge).balanceOf(address(voter));
    }

    function emergencyWithdraw(address _gauge, address _token) external onlyStrategy(_gauge) {
        voter.safeExecute(_gauge, 0, abi.encodeWithSelector(IGauge.withdrawAll.selector));
        voter.safeExecute(
            _token,
            0,
            abi.encodeWithSelector(IERC20.transfer.selector, msg.sender, IERC20(_token).balanceOf(address(voter)))
        );
    }
}
