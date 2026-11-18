# Avalanche GLP withdrawal-only proxy

`GmxProxy` is a replacement integration for the existing, deprecated Avalanche GLP strategy. It does not replace the strategy or depositor and does not move the depositor's GLP or staked GMX/esGMX during migration.

## Scope

- `withdrawGlp(uint256)` transfers staked GLP from the depositor to the immutable `glpStrategy`. Only that strategy can call it; the proxy owner cannot use it to withdraw GLP.
- `totalDeposits(address)` retains the legacy strategy selector but reads the configured fee-GLP tracker's staked amount, ignoring the caller-supplied tracker. This preserves GLP share accounting.
- `gmxRewardRouter()` remains available because the deployed strategy calls `feeGlpTracker()` on it when calculating its backing.
- `pendingRewards(address)` returns zero: GMX rewards are not WAVAX rewards available to the retired compounding strategy. The strategy's own residual WAVAX balance can still appear in its `checkReward()`.
- `claimRewards()` is owner-only. It executes `extendedGmxTracker.claim(owner())` **from the depositor**, pays liquid GMX directly to the current proxy owner, returns the claimed amount, and emits `RewardsClaimed`.
- Ownership transfers use the existing repository `Ownable` implementation. Future claims pay the new owner, not the deployer or former owner.

There is no GLP purchase, swap, staking, unstaking, vesting, arbitrary execution, generic token sweep, or strategy approval/update machinery. `claimReward(address)` and the old emergency-rescue methods are deliberately not exposed. Keep the strategy's deposits disabled and its compounding keeper disabled. The existing strategy's `rescueDeployedFunds()` will therefore revert rather than move all backing into the strategy and break its tracker-based accounting; normal user withdrawals remain supported.

## Constructor and sourced configuration

Arguments, in order:

1. `_gmxDepositor`: `0x565d72A63d3dc4a2F3Dd7609Fd85c4FD394523B2`
2. `_gmxRewardRouter`: `0xcA9b890200c9de2fD36a69f0EDaE22665DC729cD` (Avalanche RewardRouterV3)
3. `_glpStrategy`: `0x9f637540149f922145c06e1aa3f38dcDc32Aff5C`
4. `_owner`: intended reward recipient/admin; the existing strategy and depositor owner observed during verification was `0xEA3e895b0696e161C68486Ee2F85e6Cc6ef962d0`.

Re-read these values before an actual deployment. The strategy's deposit token must be Avalanche's StakedGlp transfer wrapper (`0x5643F4b25E36478eE1E90418d5343cb6591BcB9d`). The depositor must have code, the strategy must report that deposit token, and the extended tracker must report GMX (`0x62edc0692BD897D2295872a9FFCac5425011c661`) as its reward token.

Tracker addresses are resolved from the configured router at construction, not guessed:

- `extendedGmxTracker()` resolves the liquid GMX reward tracker. Its direct claim operation was tested against the live contracts on a fork.
- `feeGlpTracker()` resolves the tracker used for principal accounting.

Sources: [GMX contract docs](https://docs.gmx.io/docs/archived/contracts-v1/#staking), explorer-verified RewardRouterV3 source, and pinned-block reads of the existing strategy/depositor and trackers. Deployment artifacts `GMX-Proxy` through `GMX-Proxy-4` do not contain the most recent live proxy address.

## Migration (not executed)

1. Verify the chain, current owners, current proxy links, disabled deposits, GLP backing, share supply, and the new proxy's immutable configuration. Stop any obsolete reinvest keeper.
2. Deploy the new proxy with the intended owner/reward recipient.
3. From the existing depositor owner, call `GmxDepositor.setGmxProxy(newProxy)`.
4. From the existing strategy owner, call `strategy.setProxy(newProxy)`.
5. Prefer executing both pointer changes atomically in a single owner Safe batch. If separated, withdrawals are temporarily unavailable while the pointers disagree. No custody/account transfer, token approval, or strategy registration is needed.
6. Read both pointers back, verify unchanged backing and share supply, and verify deposit status remains disabled.
7. The new proxy owner may call `claimRewards()`; verify its GMX balance increase, emitted amount, zero residual claimable balance at that block, and unchanged GLP/staked GMX/esGMX positions.

Changing a legacy integration pointer does not itself disable deposits or keepers. This proxy deliberately cannot reinvest even if an obsolete keeper continues calling the strategy.

## Tests

Local deterministic tests (including 256 fuzz cases):

```sh
forge test --match-contract GmxProxyTest -vv
forge build --force
```

The fork suite is explicitly skipped unless `AVALANCHE_FORK_RPC_URL` is set. Run it against an Avalanche archival-capable RPC:

```sh
AVALANCHE_FORK_RPC_URL=https://avalanche.api.onfinality.io/public/ext/bc/C/rpc \
forge test \
  --rpc-url https://avalanche.api.onfinality.io/public/ext/bc/C/rpc \
  --fork-block-number 100657462 \
  --compute-units-per-second 20 \
  --match-contract GmxProxyForkTest -vv
```

The test defaults to block **100657462**, hash `0xb70106820234570526dde713c46ad3de51486d0143ddc6c9e12458c9a313d63b`, timestamp **2026-11-18 11:28:15 UTC**. Override `AVALANCHE_FORK_BLOCK` and the CLI fork block together to test a different block.

On that fork, the test deploys a real replacement proxy, impersonates the existing owner to change both authorization links, claims **104378810099118452536 wei GMX** to the owner, and executes partial then remaining-full withdrawals for an actual receipt holder, `0x8b932f5e9B62BBA7fC468396DD628aE2DD88cF33`. It verifies actual token/tracker balance changes, burned shares, unchanged GMX/esGMX stakes, unchanged pending unstake amount, and disabled deposits. No live transactions are broadcast.
