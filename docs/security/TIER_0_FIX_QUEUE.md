# Tier 0 Fix Queue — External Audit Hand-Off

> **Status:** 2026-08-20 · **Purpose:** This document is the hand-off package for the external audit firm. Per `MAINNET_READINESS.md`, Tier 0 PRs must not be merged until the external auditor signs off on each fix. This queue maps every remaining Tier 0 item to the code path, the fix shape, the test plan, and the audit gate.

> **Prerequisite:** Read `AUDIT_FINDINGS_2026-08-07.md` at the monorepo workspace root for full context on each finding.

**Execution order:** Highest risk / cheapest to fix first.

---

## Q1 — `totalVeSupply` ratchet decay (`ZENTStaking.sol:159-185`)

**Risk:** CRITICAL. Governance permanently bricks because `totalVeSupply` never decrements while individual `veBalance()` decays to 0. `ZentGovernor.quorum = totalVeSupply * quorumBps / 10000` becomes permanently unreachable. No vote can pass; governance is dead.

**File:** `contracts/src/staking/ZENTStaking.sol`, functions `withdraw()` (line 159) and `_veAt()` (line 185).

**Root cause:** `withdraw()` requires `block.timestamp >= pos.lockEnd`, but `_veAt()` returns 0 once `at >= lockEnd`. So `totalVeSupply -= oldVe` always subtracts zero. The total is incremented at stake time and never decremented. Every individual `veBalance()` decays to 0.

**Founder decision:** Implement **Curve-style checkpointed slope decay** (`_checkpoint` pattern with historical lookup). Decision recorded at `docs/decisions/2026-08-20-gov-002-ve-decay.md`.

**Fix shape (~150–250 LOC):**
- Add `Checkpoints.History` storage (`_veCheckpoints[address]`) with `_writeCheckpoint/_getCheckpointAtBlock`
- Rewrite `_veAt()` to read from checkpoint history at the requested timestamp
- Rewrite `withdraw()` to subtract the user's historical ve at withdraw-time
- Add `getPriorVeBalance(address, uint256)` public view for governor snapshots (Q7 sub-fix)
- Update `ZentGovernor._getVotes()` to use the timepoint parameter

**Test plan:**
- `contracts/test/staking/ZENTStakingVeDecay.t.sol` (NEW)
- Cases: extendLock preserves totalVeSupply, withdraw decrements totalVeSupply by historical ve, veBalance decays linearly to 0 at lockEnd, getPriorVeBalance returns correct value at past block
- `contracts/test/invariants/StakingVeSupplyInvariant.t.sol` (NEW): sum(veBalance) == totalVeSupply at every state
- `contracts/test/governance/ZentGovernorSnapshot.t.sol` (NEW): vote uses snapshot timepoint

**Audit gate:** HIGH — tokenomics decision, affects governance quorum and voting weight semantics.

---

## Q2 — Insurance routing (`ZENTStaking.sol` setter)

**Status:** 🟢 IMPLEMENTED on branch `fix/0-c-3-insurance-routing` (commit `f82b65a`). NOT merged to main (waiting for external audit sign-off per policy).

**Fix:** `setInsuranceFund(address)` requires `DEFAULT_ADMIN_ROLE`, rejects zero address via custom error `ZeroInsuranceFund()`. Constructor defaults `insuranceFund = address(0)`. `slash()` routes to `insuranceFund` if set.

**Test:** `contracts/test/staking/SlashRoutedToInsurance.t.sol` — 4 cases passing.

---

## Q3 — Single hot-key accuracy setter

**Risk:** One EOA can set arbitrary, overwritable, unverified accuracy that drives real payouts. Key compromise rewrites the entire performance record.

**File:** `contracts/src/signals/EpochScoring.sol`, function `setAccuracy()` (line 494).

**Fix shape (~30 LOC):** Replace `require(msg.sender == scoringOracle)` with `onlyRole(SCORING_ORACLE_ROLE)` using OpenZeppelin AccessControl. A Safe multisig can hold the role and rotate EOAs.

**Test plan:** `contracts/test/signals/SetAccuracyRoleGated.t.sol` (NEW). Cases: role-holder succeeds, non-holder reverts with AccessControlUnauthorizedAccount.

**Audit gate:** MEDIUM — multisig dependency.

---

## Q4 — O(n²) settlement DoS (`EpochScoring`)

**Risk:** O(n²) bubble sort + ~10 external calls per signal over an attacker-growable list. Permanent gas DoS of epoch settlement.

**File:** `contracts/src/signals/EpochScoring.sol`, function `_rankResults()` (was at line 615, comment: "Bubble sort by finalScore descending").

**Status:** 🟢 **IMPLEMENTED** on branch `fix/0-a-4-on2-sort`. NOT merged to main.

**Fix:** `EpochScoring._rankResults` rewritten with a bounded top-K selection algorithm. The protocol only rewards the top REWARD_CUTOFF (10) providers, so the sort walks `results[]` once while maintaining a descending-sorted top-K array of length 10. Total cost is O(n × K) = O(n × 10) = effectively O(n). For n=1000 the sort costs ~1.5M gas (verified by `test_rankResults_gasBounded_n1000`); pre-fix the bubble sort alone cost >100M gas and reverted with OutOfGas past a few hundred signals. Three-step algorithm: (1) bounded top-K selection via insertion-sorted top-K with back-shifts on each candidate, (2) rank assignment 1..K to top-K entries matched by provider + finalScore, (3) rank assignment K+1..n to non-top-K entries in input order for invariant hygiene. Strict-`<` shift rule preserves insertion order on ties (first encountered wins higher rank), matching the legacy bubble sort's strict-`>` swap rule — so the top-K providers selected by the new algorithm exactly match the top-K providers the old algorithm would have selected, preserving the "reward top-10" economics.

**Test:** `contracts/test/signals/EpochScoringSortDoSFix.t.sol` (NEW) — 6 cases:
- `test_rankResults_gasBounded_n1000` — sort cost < 5M for n=1000 (pre-fix: >100M).
- `test_rankResults_gasScalesLinearlyWithN` — doubling n at most triples gas (pre-fix: 4×).
- `test_rankResults_isNotON2_forLargeN` — explicit regression guard for any O(n²) revival.
- `test_rankResults_topKMatchesLegacyBubbleSort` — top-K providers match the legacy bubble sort exactly.
- `test_rankResults_ranksAreAscendingForTopK` — top-K ranks non-increasing in finalScore.
- `test_settleEpoch_n200_completesWithoutOOG` — full `settleEpoch` with n=200 signals completes (was on the OOG boundary pre-fix).

**Fix shape (50–100 LOC):** ✅ Done. Pagination / per-provider-per-epoch caps (audit recs 1 & 3) remain out-of-scope per this Q-item's narrow definition; this fix addresses the O(n²) sort component specifically. The unbounded external-call cost in `_scoreProvider` (one `getProviderStake` + five `getStakeAtEpoch` reads per signal) dominates total `settleEpoch` gas and is bounded by the underlying IZENTStaking contract, NOT by the Q4 sort fix. The audit firm's full gas-DoS recommendations (paginated/resumable settlement, break-glass `forceCloseEpoch`) require separate work items (a future Q4+).

**Audit gate:** MEDIUM.

---

## Q5 — Silent reward payout failure

**Status:** 🟢 IMPLEMENTED on branch `fix/0-b-3-reward-payout-event` (commit `ab2bb0e`). NOT merged to main.

**Fix:** `EpochScoring._distributeRewards` now emits `RewardPayoutFailed(provider, epochId, amount, reason)` from the try/catch. Persists failed amount in `failedPayouts[epochId][provider]`. Exposes `claimFailedPayouts(epochId, provider)` for post-hoc reconciliation. Adds `fundRewardPool(uint256)` (admin-only, `SafeERC20.transferFrom`).

**Test:** `contracts/test/signals/RewardPayoutFailure.t.sol` — 4 cases passing.

---

## Q6 — `accuracyCache` default-0 ≡ max-slash

**Risk:** An unscored signal is indistinguishable from a maximally-wrong one. A dead scoring oracle silently burns every provider's stake.

**File:** `contracts/src/signals/EpochScoring.sol`, `accuracyCache` mapping and `applyPayout()`.

**Status:** 🟢 **IMPLEMENTED** on branch `fix/0-a-6-accuracy-cache-default`. NOT merged to main (waiting for external audit sign-off per policy).

**Fix:** Two-part defense — (1) a per-signal sentinel `accuracyScored[signalId] : bool` that `applyPayout` requires to be `true` before reading `accuracyCache[signalId]`, so the default-zero map can never reach the slash branch by accident; (2) a recovery path `claimExpiredSignal(signalId)` (gated by `EPOCH_SETTLER`, callable only for signals older than `MAX_SIGNAL_AGE = 7 days`) that marks the signal as released without slash so off-chain observers / keepers can reconcile stale entries. New error selectors: `SignalNotScored`, `SignalStillFresh`, `ExpiredAlreadyClaimed`, `SignalAlreadyScored`. New event: `ExpiredSignalClaimed(signalId, provider, ageSeconds)`. New constant: `MAX_SIGNAL_AGE = 7 days` (tokenomics-decision window — generous enough for routine keeper outages to self-heal, short enough that a permanently-dead oracle doesn't strand signals indefinitely).

**Founder decision:** `MAX_SIGNAL_AGE = 7 days`. Recorded at `docs/decisions/2026-08-21-tier0-006-signal-recovery.md` (decision note to be added). The tokenomics trade-off is: shorter windows protect providers faster but increase keeper burden; longer windows reduce keeper churn but let signals age into "limbo" longer. 7 days is the same order of magnitude as the whitepaper §6.4 epoch-recovery story (the protocol tolerates a multi-day keeper outage as part of normal operation), and the recovery path is informational only — it does not move any ZENT.

**Test:** `contracts/test/signals/EpochScoringExpiredSignal.t.sol` (NEW) — 12 cases:
- `test_claimExpiredSignal_returnsStakeUnchanged` — recovery emits the event, flag flips, staking contract untouched (no slash, no reward).
- `test_claimExpiredSignal_emitsEvent` — `ExpiredSignalClaimed(signalId, provider, ageSeconds)` fires with correct values.
- `test_maxSignalAgeIsPubliclyReadable` — `MAX_SIGNAL_AGE()` returns 7 days.
- `test_claimExpiredSignal_revertsWhenStillFresh` — a signal 1 second inside the grace window reverts with `SignalStillFresh(age, maxAge)`.
- `test_claimExpiredSignal_succeedsAtBoundary` — a signal exactly 7 days old IS claimable (strict `<` guard).
- `test_claimExpiredSignal_revertsWhenAlreadyScored` — recovery cannot launder an intended slash.
- `test_claimExpiredSignal_revertsWhenPayoutApplied` — same protection, second guard.
- `test_applyPayoutStillRevertsAfterExpiredClaim` — defense in depth: recovery flag is informational, `applyPayout` still reverts.
- `test_claimExpiredSignal_isIdempotent` — second call reverts with `ExpiredAlreadyClaimed`.
- `test_claimExpiredSignal_distinctSignals` — releases are per-signal, no cross-contamination.
- `test_claimExpiredSignal_revertsForNonKeeper` — AccessControl revert for unprivileged callers.
- `test_claimExpiredSignal_adminCanGrantRole` — DEFAULT_ADMIN can grant EPOCH_SETTLER for governance rotation.

The pre-existing `contracts/test/signals/EpochScoringPayoutReplay.t.sol` (7 cases) already covers the sentinel half of the fix: `accuracyScored` mapping, `SignalNotScored` revert in `applyPayout`, and the related CRITICAL-2 `PayoutAlreadyApplied` guard.

**Audit gate:** MEDIUM — tokenomics parameter (`MAX_SIGNAL_AGE`).

---

## Q7 — Governor snapshot manipulation

**Risk:** Governor reads live state instead of the proposal snapshot. Any proposal can be defeated/manipulated after the fact.

**File:** `contracts/src/governance/ZentGovernor.sol`, function `_getVotes()` (line 72). Comment: "Snapshot parameter (timepoint) is ignored — veBalance is time-based, not snapshot-based."

**Fix shape:** Implicitly fixed by Q1 (checkpointed veBalance history). `_getVotes(account, timepoint)` reads from `_veCheckpoints[account]` at the timepoint.

**Test plan:** Same as Q1 governor snapshot test.

**Audit gate:** HIGH — governance semantics.

---

## Q8 — Admin-override emergency exit (`SpotVault`)

**Risk:** Oracle going quiet freezes ALL withdrawals; no fallback, no admin override. Users cannot exit.

**File:** `contracts/src/vaults/SpotVault.sol`, `redeemEmergency()` (line 372).

**Fix shape (~30 LOC):** Add `redeemEmergencyFor(address owner, uint256 shares, address receiver)` admin variant callable by `GUARDIAN_ROLE`. Preserve per-address MEV cooldown.

**Test plan:** `contracts/test/vaults/SpotVaultEmergencyAdmin.t.sol` (NEW). Cases: admin succeeds with cooldown, non-admin reverts, per-address cooldown enforced.

**Audit gate:** HIGH — admin powers.

---

## Q9 — TWAP stale-price check (vault level)

**Risk:** Stale-price window lets a depositor/redeemer extract mispricing from everyone else. Classic oracle-latency arbitrage.

**File:** `contracts/src/vaults/SpotVault.sol` and `contracts/src/vaults/BaseVault.sol`.

**Fix shape (~50 LOC):** Add TWAP / deviation check at the vault level (in addition to `MedianOracle`'s freshness check). Use `ShadowPriceOracle.latestRoundData().updatedAt` as staleness check.

**Test plan:** `contracts/test/vaults/SpotVaultStalePriceGuard.t.sol` (NEW). Cases: deposit reverts on stale price, withdraw reverts on stale price, fresh price succeeds.

**Audit gate:** HIGH — pricing model.

---

## Q10 — Per-depositor HWM equalization

**Risk:** Late depositors are retroactively taxed on gains they never received. No per-share HWM tracking.

**File:** `contracts/src/vaults/BaseVault.sol`, `evaluateFees()` uses single global `highWaterMark`.

**Fix shape (~100–150 LOC):** Add per-depositor HWM mapping. Performance fee only on gains above depositor's individual HWM.

**Test plan:** `contracts/test/vaults/BaseVaultPerDepositorHWM.t.sol` (NEW). Cases: late depositor not retroactively taxed, early depositor taxed above their HWM, both see same alpha at same time.

**Audit gate:** HIGH — fee accounting.

---

## Q11 — z-vault deprecation or live execution

**Risk:** zBTC/zETH/zSOL/zXRP cannot execute the strategy at all — yet charge a 20% performance fee and advertise "3x". Indefensible in diligence and to a regulator.

**Files:** `contracts/src/vaults/zBTCVault.sol`, `zETHVault.sol`, `zSOLVault.sol`, `zXRPVault.sol`. Each is a ~15-24 LOC wrapper around `BaseVault`.

**Founder decision:** PENDING. Options: (a) deprecated — paused, deposits blocked, withdrawals work, OR (b) wired — route through SpotVault v2 executor.

**Decision to be recorded at:** `docs/decisions/`

---

## Q12 — Backtest vs. deployed strategy reconciliation

**Risk:** The investor-facing backtest table describes a different strategy than the deployed one. This finding ends a raise.

**Scope:** Doc-only. Reconcile `data/*-model.json` and `lib/backtest.ts` with `StrategyExecutor.sol` parameters.

**Audit gate:** LOW — investor perception.

---

## Q13 — Fee-split reconciliation (3 sources)

**Risk:** Whitepaper, tokenomics page, and pitch-deck page all contradict the deployed `FeeDistributor`. Whitepaper-vs-code diff is the first thing a technical investor runs.

**Scope:** Doc-only. Canonical is `FeeDistributor.sol`: 50% Buyback / 25% Treasury / 15% Insurance / 10% GP Engine.

**Audit gate:** LOW — diligence.

---

## Q14 — "Recording live — day N" hardcoded date

**Risk:** Day counter never compared to `now`. Site showed "live" through the 30-day data outage.

**Scope:** Doc + dApp UI fix. Already partially addressed by zentory-app PR #276 (staleness gate).

---

## Q15 — Waitlist + subscriber RLS review

**Risk:** Personal-data exposure (GDPR relevance given EU ambitions).

**Scope:** zentory-app Supabase RLS policies on `whitelist` and `subscriptions` tables.

---

## Q16 — Contributor API-key expiry

**Risk:** API keys never expire, self-replicate, validated against a table absent from the schema.

**Scope:** zentory-app Supabase schema. Add `expires_at` column to `api_keys` table.

---

## Q17 — Ledger verifier enforcement

**Risk:** The tamper-evident ledger has no enforced verifier — `verify_ledger()`'s result is discarded.

**Scope:** Engine keeper crons. `ledger_guard.py` ships (zentory-engine PR #17). Single-leader EIP-712 enforcement still in flight.

---

## Summary

| # | Effort | Audit gate | Status |
|---|---|---|---|
| Q1 | ~150–250 LOC | HIGH | 🔴 OPEN — founder decision needed (decided: Curve-style) |
| Q2 | ~20 LOC (DONE) | LOW | 🟢 Branch `fix/0-c-3-insurance-routing` |
| Q3 | ~30 LOC | MEDIUM | 🔴 OPEN |
| Q4 | ~50–100 LOC | MEDIUM | 🟢 Branch `fix/0-a-4-on2-sort` |
| Q5 | ~20 LOC (DONE) | LOW | 🟢 Branch `fix/0-b-3-reward-payout-event` |
| Q6 | ~30 LOC | MEDIUM | 🟢 Branch `fix/0-a-6-accuracy-cache-default` (sentinel `accuracyScored` + `claimExpiredSignal(signalId)` recovery; `MAX_SIGNAL_AGE = 7 days`) |
| Q7 | ~50 LOC (via Q1) | HIGH | 🔴 OPEN — implicit in Q1 fix |
| Q8 | ~30 LOC | HIGH | 🔴 OPEN |
| Q9 | ~50 LOC | HIGH | 🔴 OPEN |
| Q10 | ~100–150 LOC | HIGH | 🔴 OPEN |
| Q11 | ~30 LOC or TBD | TBD | 🔴 OPEN — founder decision pending |
| Q12 | doc only | LOW | 🔴 OPEN |
| Q13 | doc only | LOW | 🔴 OPEN |
| Q14 | ~20 LOC or doc | LOW | 🟡 Partial |
| Q15 | ~10 LOC additive | LOW | 🔴 OPEN |
| Q16 | ~20 LOC | LOW | 🔴 OPEN |
| Q17 | additive | MEDIUM | 🟡 Partial |

**Estimated engineering effort:** ~6 weeks for contract items (Q1–Q11), ~1 week for doc/marketing items (Q12–Q14). Each item is a separate PR.

---

*Generated 2026-08-20 for the ZENTORY mission M2 audit-ready protocol work.*
