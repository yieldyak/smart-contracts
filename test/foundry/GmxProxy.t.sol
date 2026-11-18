// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "../../contracts/strategies/avalanche/gmx/GmxProxy.sol";
import "../../contracts/strategies/crosschain/gmx/GmxDepositor.sol";

contract MockStakedGlp {
    MockGmxRewardTracker public tracker;
    mapping(address => uint256) public balanceOf;
    bool public failTransfer;
    bool public returnFalse;

    function configure(MockGmxRewardTracker _tracker, bool _failTransfer, bool _returnFalse) external {
        tracker = _tracker;
        failTransfer = _failTransfer;
        returnFalse = _returnFalse;
    }

    function transfer(address receiver, uint256 amount) external returns (bool) {
        require(!failTransfer, "transfer reverted");
        if (returnFalse) return false;
        tracker.setStakedAmounts(msg.sender, tracker.stakedAmounts(msg.sender) - amount);
        tracker.setStakedAmounts(receiver, tracker.stakedAmounts(receiver) + amount);
        balanceOf[receiver] += amount;
        return true;
    }
}

contract MockGmxRewardTracker {
    address public rewardToken = 0x62edc0692BD897D2295872a9FFCac5425011c661;
    mapping(address => uint256) public claimable;
    mapping(address => uint256) public received;
    mapping(address => uint256) public stakedAmounts;
    bool public failClaim;

    function setRewardToken(address token) external {
        rewardToken = token;
    }

    function setStakedAmounts(address account, uint256 amount) external {
        stakedAmounts[account] = amount;
    }

    function setClaimable(address account, uint256 amount) external {
        claimable[account] = amount;
    }

    function setFailClaim(bool value) external {
        failClaim = value;
    }

    function claim(address receiver) external returns (uint256 amount) {
        require(!failClaim, "claim reverted");
        amount = claimable[msg.sender];
        claimable[msg.sender] = 0;
        received[receiver] += amount;
    }
}

contract MockGmxRewardRouter {
    address public feeGlpTracker;
    address public extendedGmxTracker;

    constructor(address glpTracker, address gmxTracker) {
        feeGlpTracker = glpTracker;
        extendedGmxTracker = gmxTracker;
    }
}

contract MockGlpStrategy {
    address public constant depositToken = 0x5643F4b25E36478eE1E90418d5343cb6591BcB9d;
}

contract WrongTokenStrategy {
    address public constant depositToken = address(1);
}

contract GmxProxyTest is Test {
    address internal constant OWNER = address(0xA11CE);
    address internal constant OTHER = address(0xB0B);
    GmxDepositor internal depositor;
    MockGmxRewardTracker internal tracker;
    MockGmxRewardTracker internal glpTracker;
    MockGmxRewardRouter internal router;
    MockGlpStrategy internal strategy;
    MockStakedGlp internal fsGlp;
    GmxProxy internal proxy;

    function setUp() public {
        depositor = new GmxDepositor(address(this));
        tracker = new MockGmxRewardTracker();
        glpTracker = new MockGmxRewardTracker();
        router = new MockGmxRewardRouter(address(glpTracker), address(tracker));
        strategy = new MockGlpStrategy();
        proxy = new GmxProxy(address(depositor), address(router), address(strategy), OWNER);
        depositor.setGmxProxy(address(proxy));

        MockStakedGlp token = new MockStakedGlp();
        vm.etch(strategy.depositToken(), address(token).code);
        fsGlp = MockStakedGlp(strategy.depositToken());
        fsGlp.configure(glpTracker, false, false);
        glpTracker.setStakedAmounts(address(depositor), 100 ether);
    }

    function testConstructorRejectsDepositorWithoutCode() public {
        vm.expectRevert("GmxProxy::invalid depositor");
        new GmxProxy(address(1), address(router), address(strategy), OWNER);
    }

    function testConstructorRejectsNonGmxRewardTracker() public {
        tracker.setRewardToken(strategy.depositToken());
        vm.expectRevert("GmxProxy::invalid reward token");
        new GmxProxy(address(depositor), address(router), address(strategy), OWNER);
    }

    function testConstructorRejectsNonGlpStrategy() public {
        WrongTokenStrategy wrong = new WrongTokenStrategy();
        vm.expectRevert("GmxProxy::invalid strategy");
        new GmxProxy(address(depositor), address(router), address(wrong), OWNER);
    }

    function testConstructorRejectsZeroOwner() public {
        vm.expectRevert("Ownable: new owner is the zero address");
        new GmxProxy(address(depositor), address(router), address(strategy), address(0));
    }

    function testConfigurationMatchesConstructor() public {
        assertEq(proxy.owner(), OWNER);
        assertEq(address(proxy.gmxDepositor()), address(depositor));
        assertEq(proxy.gmxRewardRouter(), address(router));
        assertEq(proxy.glpStrategy(), address(strategy));
        assertEq(address(proxy.gmxRewardTracker()), address(tracker));
        assertEq(address(proxy.feeGlpTracker()), address(glpTracker));
    }

    function testPendingRewardsExcludesOwnerGmxRewards() public {
        tracker.setClaimable(address(depositor), 104 ether);
        assertEq(proxy.pendingRewards(address(tracker)), 0);
    }

    function testAccountingCannotBeRedirectedToAnArbitraryTracker() public {
        assertEq(proxy.totalDeposits(address(0)), 100 ether);
        assertEq(proxy.totalDeposits(OTHER), 100 ether);
    }

    function testStrategyWithdrawsGlpAndAccountingFalls() public {
        vm.prank(address(strategy));
        proxy.withdrawGlp(40 ether);
        assertEq(fsGlp.balanceOf(address(strategy)), 40 ether);
        assertEq(proxy.totalDeposits(address(tracker)), 60 ether);
    }

    function testFuzzStrategyCanWithdrawUpToEntireBacking(uint256 amount) public {
        amount = bound(amount, 0, 100 ether);
        vm.prank(address(strategy));
        proxy.withdrawGlp(amount);
        assertEq(fsGlp.balanceOf(address(strategy)), amount);
        assertEq(proxy.totalDeposits(address(tracker)), 100 ether - amount);
    }

    function testOwnerCannotWithdrawGlp() public {
        vm.prank(OWNER);
        vm.expectRevert("GmxProxy::onlyGLPStrategy");
        proxy.withdrawGlp(1 ether);
    }

    function testUnrelatedCallerCannotWithdrawGlp() public {
        vm.prank(OTHER);
        vm.expectRevert("GmxProxy::onlyGLPStrategy");
        proxy.withdrawGlp(1 ether);
    }

    function testWithdrawPropagatesFailedDepositorCall() public {
        fsGlp.configure(glpTracker, true, false);
        vm.prank(address(strategy));
        vm.expectRevert("GmxProxy::execute failed");
        proxy.withdrawGlp(1 ether);
        assertEq(proxy.totalDeposits(address(tracker)), 100 ether);
    }

    function testWithdrawRejectsFalseTokenReturn() public {
        fsGlp.configure(glpTracker, false, true);
        vm.prank(address(strategy));
        vm.expectRevert("GmxProxy::transfer failed");
        proxy.withdrawGlp(1 ether);
        assertEq(proxy.totalDeposits(address(tracker)), 100 ether);
    }

    function testOwnerClaimsDepositorRewardsDirectlyToOwner() public {
        tracker.setClaimable(address(depositor), 104 ether);
        vm.prank(OWNER);
        assertEq(proxy.claimRewards(), 104 ether);
        assertEq(tracker.received(OWNER), 104 ether);
        assertEq(tracker.received(address(proxy)), 0);
        assertEq(tracker.received(address(depositor)), 0);
        assertEq(tracker.claimable(address(depositor)), 0);
        assertEq(proxy.totalDeposits(address(tracker)), 100 ether);
    }

    function testNonOwnerCannotClaim() public {
        vm.prank(OTHER);
        vm.expectRevert("Ownable: caller is not the owner");
        proxy.claimRewards();
    }

    function testStrategyCannotClaimOwnerRewards() public {
        vm.prank(address(strategy));
        vm.expectRevert("Ownable: caller is not the owner");
        proxy.claimRewards();
    }

    function testClaimFollowsOwnershipTransfer() public {
        tracker.setClaimable(address(depositor), 104 ether);
        vm.prank(OWNER);
        proxy.transferOwnership(OTHER);
        vm.prank(OWNER);
        vm.expectRevert("Ownable: caller is not the owner");
        proxy.claimRewards();
        vm.prank(OTHER);
        proxy.claimRewards();
        assertEq(tracker.received(OTHER), 104 ether);
        assertEq(tracker.received(OWNER), 0);
    }

    function testClaimDoesNotDoublePay() public {
        tracker.setClaimable(address(depositor), 104 ether);
        vm.startPrank(OWNER);
        assertEq(proxy.claimRewards(), 104 ether);
        assertEq(proxy.claimRewards(), 0);
        vm.stopPrank();
        assertEq(tracker.received(OWNER), 104 ether);
    }

    function testClaimPropagatesFailedDepositorCall() public {
        tracker.setClaimable(address(depositor), 104 ether);
        tracker.setFailClaim(true);
        vm.prank(OWNER);
        vm.expectRevert("GmxProxy::execute failed");
        proxy.claimRewards();
        assertEq(tracker.claimable(address(depositor)), 104 ether);
    }

    function testClaimRequiresDepositorAuthorization() public {
        depositor.setGmxProxy(OTHER);
        vm.prank(OWNER);
        vm.expectRevert("GmxDepositor::onlyGmxProxy");
        proxy.claimRewards();
    }

    function testRemovedOperationsAreUnavailable() public {
        bytes[5] memory calls = [
            abi.encodeWithSignature("buyAndStakeGlp(uint256)", 1 ether),
            abi.encodeWithSignature("stakeGmx(uint256)", 1 ether),
            abi.encodeWithSignature("withdrawGmx(uint256)", 1 ether),
            abi.encodeWithSignature("claimReward(address)", address(tracker)),
            abi.encodeWithSignature("sweep(address)", strategy.depositToken())
        ];
        for (uint256 i; i < calls.length; ++i) {
            vm.prank(OWNER);
            (bool success,) = address(proxy).call(calls[i]);
            assertFalse(success);
        }
    }
}
