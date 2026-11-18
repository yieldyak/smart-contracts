// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "forge-std/Test.sol";
import "../../contracts/strategies/avalanche/gmx/GmxProxy.sol";
import "../../contracts/strategies/crosschain/gmx/interfaces/IGmxDepositor.sol";
import "../../contracts/interfaces/IERC20.sol";

interface VmSkip {
    function skip(bool condition) external;
}

interface IForkGmxDepositor is IGmxDepositor {
    function proxy() external view returns (address);
}

interface ILegacyGlpStrategy {
    function owner() external view returns (address);
    function proxy() external view returns (address);
    function setProxy(address newProxy) external;
    function DEPOSITS_ENABLED() external view returns (bool);
    function totalDeposits() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function getDepositTokensForShares(uint256 shares) external view returns (uint256);
    function checkReward() external view returns (uint256);
    function withdraw(uint256 shares) external;
}

interface IForkGmxTracker {
    function claimable(address account) external view returns (uint256);
    function depositBalances(address account, address token) external view returns (uint256);
    function stakedAmounts(address account) external view returns (uint256);
}

interface IForkGmxRouter {
    function stakedGmxTracker() external view returns (address);
    function stakedGlpTracker() external view returns (address);
    function pendingUnstakeAmount(address account) external view returns (uint256);
}

contract GmxProxyForkTest is Test {
    address internal constant STRATEGY = 0x9f637540149f922145c06e1aa3f38dcDc32Aff5C;
    address internal constant DEPOSITOR = 0x565d72A63d3dc4a2F3Dd7609Fd85c4FD394523B2;
    address internal constant ROUTER = 0xcA9b890200c9de2fD36a69f0EDaE22665DC729cD;
    // Routescan's largest receipt holder; balance is verified on the fork, not assumed.
    address internal constant HOLDER = 0x8b932f5e9B62BBA7fC468396DD628aE2DD88cF33;
    address internal constant GMX = 0x62edc0692BD897D2295872a9FFCac5425011c661;
    address internal constant ESGMX = 0xFf1489227BbAAC61a9209A08929E4c2a526DdD17;
    ILegacyGlpStrategy internal strategy = ILegacyGlpStrategy(STRATEGY);
    GmxProxy internal proxy;
    address internal owner;

    function setUp() public {
        string memory rpc = vm.envOr("AVALANCHE_FORK_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            VmSkip(address(vm)).skip(true);
            return;
        }
        vm.createSelectFork(rpc, vm.envOr("AVALANCHE_FORK_BLOCK", uint256(100657462)));
        assertEq(block.chainid, 43114);
        owner = strategy.owner();
        assertFalse(strategy.DEPOSITS_ENABLED());
        uint256 backingBefore = strategy.totalDeposits();
        uint256 supplyBefore = strategy.totalSupply();
        IForkGmxTracker stakedGlp = IForkGmxTracker(IForkGmxRouter(ROUTER).stakedGlpTracker());
        uint256 custodyGlpBefore = stakedGlp.stakedAmounts(DEPOSITOR);
        IForkGmxTracker stakedGmx = IForkGmxTracker(IForkGmxRouter(ROUTER).stakedGmxTracker());
        uint256 esStakeBefore = stakedGmx.depositBalances(DEPOSITOR, ESGMX);
        uint256 gmxStakeBefore = stakedGmx.depositBalances(DEPOSITOR, GMX);
        uint256 requestsBefore = IForkGmxRouter(ROUTER).pendingUnstakeAmount(DEPOSITOR);
        proxy = new GmxProxy(DEPOSITOR, ROUTER, STRATEGY, owner);

        // Local fork only: migrate both pointers without moving custody or stakes.
        vm.startPrank(owner);
        IGmxDepositor(DEPOSITOR).setGmxProxy(address(proxy));
        strategy.setProxy(address(proxy));
        vm.stopPrank();
        assertEq(strategy.proxy(), address(proxy));
        assertEq(IForkGmxDepositor(DEPOSITOR).proxy(), address(proxy));
        assertEq(strategy.totalDeposits(), backingBefore);
        assertEq(strategy.totalSupply(), supplyBefore);
        assertEq(stakedGlp.stakedAmounts(DEPOSITOR), custodyGlpBefore);
        assertEq(stakedGmx.depositBalances(DEPOSITOR, ESGMX), esStakeBefore);
        assertEq(stakedGmx.depositBalances(DEPOSITOR, GMX), gmxStakeBefore);
        assertEq(IForkGmxRouter(ROUTER).pendingUnstakeAmount(DEPOSITOR), requestsBefore);
        assertFalse(strategy.DEPOSITS_ENABLED());
    }

    function testClaimToOwnerThenRealHolderWithdrawsWithoutChangingGmxStake() public {
        uint256 backing = strategy.totalDeposits();
        uint256 supply = strategy.totalSupply();
        uint256 pendingRequests = IForkGmxRouter(ROUTER).pendingUnstakeAmount(DEPOSITOR);
        address stakedGmx = IForkGmxRouter(ROUTER).stakedGmxTracker();
        uint256 esStake = IForkGmxTracker(stakedGmx).depositBalances(DEPOSITOR, ESGMX);
        uint256 gmxStake = IForkGmxTracker(stakedGmx).depositBalances(DEPOSITOR, GMX);
        uint256 expected = IForkGmxTracker(address(proxy.gmxRewardTracker())).claimable(DEPOSITOR);
        uint256 ownerBalance = IERC20(GMX).balanceOf(owner);
        uint256 custodyBalance = IERC20(GMX).balanceOf(DEPOSITOR);
        assertGt(expected, 0);

        vm.prank(owner);
        uint256 claimed = proxy.claimRewards();
        assertEq(claimed, expected);
        assertEq(IERC20(GMX).balanceOf(owner), ownerBalance + expected);
        assertEq(IERC20(GMX).balanceOf(DEPOSITOR), custodyBalance);
        assertEq(IERC20(GMX).balanceOf(address(proxy)), 0);
        assertEq(IForkGmxTracker(address(proxy.gmxRewardTracker())).claimable(DEPOSITOR), 0);
        assertEq(strategy.totalDeposits(), backing);
        assertEq(strategy.totalSupply(), supply);
        assertEq(IForkGmxTracker(stakedGmx).depositBalances(DEPOSITOR, ESGMX), esStake);
        assertEq(IForkGmxTracker(stakedGmx).depositBalances(DEPOSITOR, GMX), gmxStake);
        assertEq(IForkGmxRouter(ROUTER).pendingUnstakeAmount(DEPOSITOR), pendingRequests);
        // checkReward must remain readable, but no GMX is advertised as compoundable WAVAX.
        strategy.checkReward();

        _withdrawHolderShares(strategy.balanceOf(HOLDER) / 3);
        _withdrawHolderShares(strategy.balanceOf(HOLDER));
        assertEq(strategy.balanceOf(HOLDER), 0);
        assertFalse(strategy.DEPOSITS_ENABLED());
        assertEq(IForkGmxTracker(stakedGmx).depositBalances(DEPOSITOR, ESGMX), esStake);
        assertEq(IForkGmxTracker(stakedGmx).depositBalances(DEPOSITOR, GMX), gmxStake);

        emit log_named_uint("GMX claimed to owner (wei)", claimed);
        emit log_named_uint("GLP backing before holder withdrawals (wei)", backing);
        emit log_named_uint("GLP backing after holder withdrawals (wei)", strategy.totalDeposits());
    }

    function _withdrawHolderShares(uint256 shares) private {
        assertGt(shares, 0);
        uint256 expected = strategy.getDepositTokensForShares(shares);
        uint256 backing = strategy.totalDeposits();
        uint256 supply = strategy.totalSupply();
        address stakedGlp = IForkGmxRouter(ROUTER).stakedGlpTracker();
        uint256 userGlp = IForkGmxTracker(stakedGlp).stakedAmounts(HOLDER);
        vm.prank(HOLDER);
        strategy.withdraw(shares);
        assertEq(IForkGmxTracker(stakedGlp).stakedAmounts(HOLDER), userGlp + expected);
        assertEq(strategy.totalDeposits(), backing - expected);
        assertEq(strategy.totalSupply(), supply - shares);
    }
}
