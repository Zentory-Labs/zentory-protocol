# Redeploy the signal scoring stack (testnet 998)

**Why:** the deployed `ZENTStaking` (`0x4E2e7Fd3…`, from the 2026-04-27 core deploy) is
stale bytecode — its `getProviderStake` **reverts** for any unstaked address. `EpochScoring.settleEpoch`
calls it unguarded in the totalStake loop, so the keeper **bricks on the first non-empty epoch**
(observed 2026-06-03 on epoch 11). Current source returns `0` (no revert). `EpochScoring.zentStaking`
is immutable (no setter), so the staking can only be swapped by redeploying the scoring contracts too.

This redeploys **ZENTStaking + SignalRegistry + EpochScoring** fresh from current `main` and wires
everything in one broadcast. Fixes all three known issues at once:
1. stale staking (the blocker), 2. epoch off-by-one (source `currentEpochId=1`), 3. role hygiene
(deployer bootstrap `SCORING_ORACLE` revoked).

**Kept as-is (independent of the scoring stack — do NOT redeploy or re-point):** ZENT token,
SubscriptionVault `0xb053b9a1…`, all 4 vaults, the BTC price feed `0x46a7c01424229CB5B2C9FF069e6b0eab07490Fd4`
(the oracle pusher keeps it fresh; the new EpochScoring re-uses it).

Dry-run verified: deploys cleanly, all roles wire, epoch counters align at 1, BTC feed set,
`getProviderStake` returns 0 (not revert), deployer bootstrap role revoked. Gas ≈ 0.0016 HYPE
(deployer has ~0.087).

---

## Step 1 — Broadcast the redeploy (you, deployer key)

From `zentory-protocol/contracts` (PRIVATE_KEY is read from `.env`):

```powershell
pwsh ./redeploy-signal-stack.ps1
```

It prints **three new addresses** — copy them:

```
ZENT_STAKING=    0x…
SIGNAL_REGISTRY= 0x…
EPOCH_SCORING=   0x…
```

The script asserts every wiring invariant before returning; if any fails it reverts and nothing
is half-deployed. Use the addresses **it prints** (not the dry-run's predictions — those depend on nonce).

## Step 2 — Re-point the keeper (Railway → `keeper-settle`)

Service `9b48d603-…` in project `vibrant-essence`. Update env vars, then redeploy the service:

| Var | New value |
|---|---|
| `SIGNAL_REGISTRY_ADDRESS` | new SignalRegistry |
| `EPOCH_SCORING_ADDRESS`   | new EpochScoring |
| `STAKING_ADDRESS`         | new ZENTStaking |

## Step 3 — Re-point the engine (Railway engine services + local `.env`)

`signal_submitter.py`, `demo_seed_signals.py`, `scripts/index_signal_arena.py` all read
`SIGNAL_REGISTRY_ADDRESS`. Set it to the new SignalRegistry everywhere the engine runs.
(The oracle pusher targets the price feed, which is unchanged — leave it.)

Reset the indexer so it scans from the new registry's deploy block, not the old one:
```sql
delete from public.provider_stats;
delete from public.indexer_state;
```
Set `REGISTRY_FROM_BLOCK` (index_signal_arena env) to the block the redeploy mined in (from the
broadcast receipt), so the first run doesn't rescan all of history.

## Step 4 — Re-point the dApp (`zentory-app/lib/contracts.ts`)

```
line 28: ZENTStaking:     "0x4E2e7Fd3…"  → new ZENTStaking
line 55: SignalRegistry:  "0x9685F25E…"  → new SignalRegistry
line 56: EpochScoring:    "0x31b7082f…"  → new EpochScoring
```
Commit + push to `main` → Vercel auto-deploys. (NEXT_PUBLIC_ values are baked at build, so a
redeploy is required — the push triggers it.)

## Step 5 — Update docs / memory

- `zentory-protocol/contracts/DEPLOYMENTS.md` + `STATE.md` — new 3 addresses; mark the old set superseded.
- memory `deployments-testnet.md` — canonical signal addresses.

## Step 6 — Verify the loop scores end-to-end

1. Submitter posts into the new registry's open epoch (1).
2. Keeper settles epoch 1 once its window closes → with a signal present it now runs the **full
   scoring path** without reverting (fresh staking's `getProviderStake` returns 0).
3. Watch for a `SignalScored` event + `EpochSettled` with `settledSignals > 0`; leaderboard
   accuracy populates via the indexer.

Quick on-chain checks (replace $REG/$SCO with the new addresses):
```bash
cast call $REG "currentEpochId()(uint256)" --rpc-url https://rpc.hyperliquid-testnet.xyz/evm
cast call $SCO "currentEpochId()(uint256)" --rpc-url https://rpc.hyperliquid-testnet.xyz/evm   # must equal $REG
cast call $SCO "settleEpoch()" --from 0x2251F2D8541f5D5263316E2921611c74D6d30D94 --rpc-url …    # must NOT revert
```

---

**Note on the current (old) deployment:** the re-sync + revoke done on 2026-06-03 left the OLD
registry `0x9685…` aligned at epoch 11 and hardened, but it points at the stale staking and cannot
score non-empty epochs. Once the new stack is live and re-pointed, the old signal contracts are
abandoned (their historical signals were never scoreable anyway). No migration of state is needed
on testnet.
