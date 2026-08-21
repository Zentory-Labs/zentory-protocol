# Tier 0 Fix Queue

> **Status:** planning skeleton. Not yet implementation-ready. Each item below has
> a planned fix shape, a planned test, and the external-audit gate that must be
> satisfied before any merge. **Do NOT start implementing these from this
> document** — each needs a dedicated PR that:
> 1. Starts from a fresh `main` after the external audit report lands.
> 2. Includes a Foundry PoC that reproduces the finding on `main`.
> 3. Implements the minimum fix.
> 4. Adds a regression test that fails on the unfixed code.
> 5. Gets the external auditor to sign off on the fix.
>
> Source: `docs/MAINNET_READINESS.md` Tier 0 + the per-finding detail at
> `AUDIT_FINDINGS_2026-08-07.md` (when that file is created).

This is the queue we hand to the external audit firm. Order is "highest risk /
cheapest to fix first."

---

## Queue (in execution order)

### Q1 — [0.C.1] `totalVeSupply` ratchets up forever → governance bricks permanently
- **Risk:** governance permanently un-passable, irreversible.
- **File:** `contracts/src/staking/ZENTStaking.sol:159` (the `withdraw()` path).
- **Root cause:** `_veAt()` returns 0 once `at >= lockEnd` (:185), so
  `totalVeSupply -= oldVe` (:164) always subtracts zero.
- **Decision required (founder):**
  - Option A: Curve-style checkpointed slope decay (full accounting rewrite).
  - Option B: Base `ZentGovernor.quorum` on `totalStaked()` instead (tokenomics
    change, requires governance vote to ratify).
- **Fix shape (Option A):** replace `_veAt()` with a slope-based decay that
  returns 0 only at `lockEnd`, plus a `_veAt(blockNumber)` overload the quorum
  math can use. ~150–250 LOC + storage restructure.
- **PoC:** deploy `ZENTStaking` in Foundry, stake, advance past `lockEnd`,
  withdraw, observe `totalVeSupply` unchanged. Expected to be a one-line test
  once the regression test is written.
- **Test:** `contracts/test/staking/VeSupplyDecay.t.sol` — stake → wait →
  withdraw → assert `totalVeSupply == 0`.
- **Audit gate:** requires tokenomics decision AND auditor sign-off on the
  accounting shape.

### Q2 — [0.C.3] Slashed ZENT unrecoverable — insurance defaults to `address(this)`
- **Risk:** real value burned into a black hole after any slash.
- **File:** `contracts/src/staking/ZENTStaking.sol` constructor / storage.
- **Fix shape:** add `insuranceFund` setter (admin-only), initialize to the
  deployed `InsuranceFund.sol` address during mainnet deploy.
- **Test:** `contracts/test/staking/SlashRoutedToInsurance.t.sol` — slash a
  provider, observe ZENT balance moves to `InsuranceFund` not `address(this)`.
- **Audit gate:** low — straightforward setter. Pre-audit review OK.

### Q3 — [0.B.4] Single hot-key accuracy setter
- **Risk:** one key compromise rewrites the entire performance record.
- **File:** `contracts/src/signals/EpochScoring.sol` constructor (`scoringOracle`).
- **Fix shape:** require `scoringOracle` to be a contract (interface check) OR
  require multi-sig role assignment. The `setAccuracy` path already has
  `onlyRole(EPOCH_SETTLER)` (self-audit C-1); the gap is the role is granted to
  a single EOA by default.
- **Test:** `contracts/test/signals/ScoringOracleRoleCheck.t.sol` — assert
  `scoringOracle` cannot be `address(0)` or an EOA without multisig role
  grant; assert non-role-holders revert.
- **Audit gate:** medium — depends on the multisig migration in
  `MigrateToMultisig.s.sol` landing first.

### Q4 — [0.B.2] O(n²) sort + unbounded external calls per signal
- **Risk:** permanent gas DoS of epoch settlement.
- **File:** `contracts/src/signals/EpochScoring.sol::_distributeRewards()`.
- **Fix shape:** replace the in-loop sort with a priority-queue approach OR cap
  the per-epoch signal list size with a new bounded accumulator (signals older
  than N epochs auto-settle at default accuracy).
- **Test:** `contracts/test/signals/EpochDoS.t.sol` — submit 1000 signals,
  observe settlement gas < 10M (or whatever the auditor recommends as the cap).
- **Audit gate:** medium — algorithmic change, needs auditor review of the
  boundary cases.

### Q5 — [0.B.3] Reward payouts silently never execute
- **Risk:** providers slashed but never paid — incentive model inverted.
- **File:** `contracts/src/signals/EpochScoring.sol` (`_distributeRewards` +
  allowance on the `ZENTStaking` reward path).
- **Fix shape:** add an explicit `RewardPayoutFailed` event in the existing
  try/catch (line 399); add a keeper-visible `claimFailedPayouts(provider)`
  function so the missed payouts can be reconciled post-hoc. The
  `epochReward / results.length` allowance check needs an explicit `approve`
  flow at deploy time.
- **Test:** `contracts/test/signals/RewardPayoutFailure.t.sol` — simulate a
  provider with no stake, observe `RewardPayoutFailed` event, observe
  `claimFailedPayouts` works after the fact.
- **Audit gate:** low — additive, no behavior change for the happy path.

### Q6 — [0.B.1] `accuracyCache` defaults to 0 ≡ maximum slash
- **Risk:** dead scoring oracle silently burns every provider's stake.
- **File:** `contracts/src/signals/EpochScoring.sol::applyPayout()`.
- **Current mitigation:** the `if (!accuracyScored[signalId]) revert
  SignalNotScored` guard at line 437.
- **Gap:** providers can still submit signals that never get scored (e.g.,
  keeper bot crashes before `setAccuracy` runs) — those signals are now stuck
  and the stake is locked indefinitely.
- **Fix shape:** add a `claimExpiredSignal(signalId)` keeper-gated path that
  returns the stake without slash for signals older than `MAX_SIGNAL_AGE` with
  no accuracy recorded.
- **Test:** `contracts/test/signals/ExpiredSignalClaim.t.sol` — submit signal,
  advance time past `MAX_SIGNAL_AGE`, observe `claimExpiredSignal` returns
  stake without penalty.
- **Audit gate:** medium — tokenomics decision (do unscored signals count
  against providers?).

### Q7 — [0.C.2] Governor reads live state instead of proposal snapshot
- **Risk:** post-fact proposal manipulation.
- **File:** `contracts/src/governance/ZentGovernor.sol` + `ZentStaking.sol`.
- **Fix shape:** extend OpenZeppelin `Governor` to read `getPriorVotes` (or
  equivalent) at the proposal's `voteStart` block, not at execution. The
  current `OZVotes` extension uses a snapshot pattern; verify it's wired
  correctly.
- **Test:** `contracts/test/governance/ProposalSnapshot.t.sol` — submit a
  proposal, advance block, change `veBalance` of a voter, observe the proposal
  outcome reflects the snapshot not the live state.
- **Audit gate:** high — governance semantics change.

### Q8 — [0.A.4] Admin-override path on stale oracle
- **Risk:** users cannot exit if oracle goes quiet.
- **Current mitigation:** `SpotVault.redeemEmergency` ships (PR #65) with a
  1-hour MEV cooldown.
- **Gap:** admin override still missing — admins cannot trigger emergency
  redemption on behalf of users, only users themselves can (with cooldown).
- **Status:** 🟢 **IMPLEMENTED** on branch `fix/0-a-8-admin-emergency-exit`
  (Q8 PR; awaiting external-audit sign-off per policy; not yet on `main`).
- **Fix shape (delivered):** add `redeemEmergencyFor(address owner, uint256
  shares, address receiver)` admin variant callable by `RISK_COUNCIL_ROLE` (the
  existing on-chain role already gated to the 4/7 Safe / founder multisig on
  mainnet). Preserves per-address MEV cooldown — the admin path uses the SAME
  `lastEmergencyRedeemAt[owner]` key as the user path, so:
  - The admin CAN burn a victim's shares on the victim's behalf during an
    incident response (e.g. when the victim's UI is down or the victim is
    unreachable).
  - The admin CANNOT bypass the cooldown for the victim — every admin call
    advances `lastEmergencyRedeemAt[owner]` by `emergencyRedeemCooldown`
    identically to a user-initiated call.
  - The admin CANNOT drain a victim's shares after the victim has revoked
    allowance — standard ERC-4626 allowance semantics, mirrored from
    `redeemEmergency`.
  - The circuit-breaker halts the admin path explicitly
    (`EmergencyBreakerActive`).
  - Cooldown is per-`owner`, not per-caller — admin acting for alice does NOT
    consume bob's cooldown clock.
- **Event:** emits the same `EmergencyRedeem(caller, receiver, owner,
  shares, paid, haircutAssets, haircutPerShare)` event with
  `caller = msg.sender` (the admin) so off-chain monitors can distinguish
  admin-initiated exits from user exits.
- **Test:** `contracts/test/vaults/SpotVaultEmergencyAdminOverride.t.sol`
  (NEW) — 11 cases:
  - `test_redeemEmergencyFor_adminCanBurnOwnerShares` — admin override pays
    `receiver` from `owner`'s share balance.
  - `test_redeemEmergencyFor_nonAdminReverts` — stranger / owner /
    `DEFAULT_ADMIN_ROLE`-only all revert; riskCouncil succeeds.
  - `test_redeemEmergencyFor_preservesPerAddressCooldown` — second admin
    call for same owner reverts with `EmergencyCooldownActive` at the same
    boundary as user-initiated.
  - `test_redeemEmergencyFor_cooldownIsPerOwner_notPerCaller` — admin acting
    for alice does NOT consume bob's cooldown clock; per-owner isolation
    property (VAL-PROTO-052 / VAL-PROTO-060).
  - `test_redeemEmergencyFor_revertsOnCircuitBreaker` — circuit-breaker
    halts admin path explicitly.
  - `test_redeemEmergencyFor_revokedAllowanceReverts` — admin cannot burn
    a victim's shares when victim has zero / partial allowance.
  - `test_redeemEmergencyFor_insufficientAllowanceReverts` — admin path
    respects allowance boundary (does not silently fall through).
  - `test_redeemEmergencyFor_zeroSharesReverts` /
    `test_redeemEmergencyFor_zeroAddrReverts` — input validation.
  - `test_redeemEmergencyFor_emitsEventWithAdminCaller` — event identifies
    the admin as `caller` for off-chain monitors.
  - `test_redeemEmergencyFor_ownerCooldownIsMonotonicAcrossPaths` — the
    VAL-PROTO-060 invariant: owner's cooldown clock ticks whether the
    redeem is user-initiated OR admin-initiated; further calls inside the
    window revert at the same boundary.
- **Suite impact:** 11 new tests. Full Foundry suite passes 394/0/1
  (was 383/0/1 pre-fix).
- **Audit gate:** high — admin powers on user funds.

### Q9 — [0.A.1] Stale-price window arbitrage
- **Risk:** depositor/redeemer extracts mispricing.
- **File:** `BaseVault.sol` (and `SpotVault.sol`).
- **Fix shape:** add a TWAP check on oracle updates (e.g., reject if the new
  price is >X% away from the time-weighted average over the last N minutes).
  `MedianOracle` already multi-sources, but the freshness vs. deviation check
  is at the vault level.
- **Test:** `contracts/test/vaults/TwapCheck.t.sol` — submit an adversarial
  oracle update that moves price 10% in 1 minute, observe revert.
- **Audit gate:** high — pricing model change.
- **Status:** 🟢 **IMPLEMENTED** on branch `fix/0-a-9-stale-price-twap` (Q9 PR;
  awaiting external-audit sign-off per policy; not yet on `main`).
- **Fix shape (delivered):** the SpotVault contract now maintains a rolling
  TWAP over a `twapWindow` (default 30 min, immutable) of recent on-chain
  price observations (16-slot ring buffer). Every state-changing entry
  point (`rebalanceTo`, `_deposit`, `_withdraw`, plus a new
  `seedOracleObservation()` for the oracle-pusher service) records an
  observation. The view-path `_oraclePrice()` reads the oracle and checks
  the deviation against the rolling TWAP — if the deviation reaches or
  exceeds `maxOracleDeviationBps` (default 1000 = 10%), the vault reverts
  with `OracleDeviationTooLarge(uint256 currentPrice, uint256 twapPrice,
  uint256 maxDeviationBps)`. The MedianOracle freshness bound
  (`maxOracleStaleness`) is preserved as the FIRST line of defence; the
  deviation guard is the SECOND.
- **Admin override:** `setMaxOracleDeviationBps(uint256 newBps)` is
  `DEFAULT_ADMIN_ROLE` — settable for incident response without redeploy.
  Setting to 0 disables the guard (legacy pre-fix behaviour).
- **Cold-start safety:** the first observation seeds the TWAP (no deviation
  check fires on the seed). The guard only fires on the SECOND observation
  that would deviate from the running TWAP. After all observations evict
  from the window (e.g. after 30 min of no activity), the next observation
  re-seeds the TWAP — same cold-start semantics.
- **Error:** `OracleDeviationTooLarge(currentPrice, twapPrice, maxDeviationBps)`
  (custom error with structured fields for off-chain monitoring).
- **Events:** `MaxOracleDeviationBpsSet(oldBps, newBps)`;
  `OracleDeviationRecorded(currentPrice, twapPrice, deviationBps, maxDeviationBps, observationCount)`.
- **Test cases (one per Q9 sub-assertion):**
  - `test_deviationGuard_reverts_whenJumpingAboveThreshold` — VL-PROTO-061:
    an adversarial 10% jump from a seeded TWAP reverts with
    `OracleDeviationTooLarge` carrying the deviation context.
  - `test_deviationGuard_acceptance_whenWithinThreshold` — a 1% move from
    the seeded TWAP is accepted (no revert); the vault computes a fresh
    NAV per share.
  - `test_deviationGuard_noObservationsDoesNotPanic` — VL-PROTO-061
    cold-start: the first observation seeds the TWAP; the guard fires on
    the SECOND observation that deviates.
  - `test_deviationGuard_rebalanceBlocked` — the keeper rebalance path
    (Q9 fix shape: the keeper's `rebalanceTo(uint16)`) is gated by the
    deviation guard; the vault halts on adversarial price rather than
    transacting.
  - `test_deviationGuard_depositBlocked` — the deposit/mint path is gated
    the same way (depositor cannot extract mispricing by minting cheap
    shares against a stale-but-fresh answer).
  - `test_deviationGuard_adminCanSetThreshold` — admin can adjust the
    threshold (incident response): loosening to 50% accepts the spike.
  - `test_deviationGuard_adminCanDisable` — admin can set the threshold to
    0 to disable the guard (legacy pre-fix behaviour).
  - `test_deviationGuard_nonAdminCannotPause` — non-admin cannot change
    the threshold (AccessControl).
  - `test_deviationGuard_windowEvictsOldObservations` — observations older
    than `twapWindow` are evicted from the TWAP computation; the next
    observation re-seeds the TWAP.
  - `test_constructor_acceptsZeroDeviation_disablesGuard` — constructor
    validates `maxOracleDeviationBps == 0` is accepted (disables guard).
  - `test_constructorRejectsDeviationAboveBps` — constructor rejects
    `maxOracleDeviationBps > 10000` (i.e. > 100% deviation).
  - `test_deviationGuard_stalenessGuardStillFires` — the staleness guard
    fires FIRST; the deviation guard is the SECOND line of defence.
  - `test_deviationGuard_e2e_longRebalanceAcceptsWithinThreshold` —
    end-to-end: a 1% move lets the keeper complete a rebalance to fully
    long.
  - `test_deviationGuard_emitsEventOnRevert` — the revert carries the
    deviation context for off-chain monitoring.
  - `test_regressionTestPreFixVault_acceptsAdversarialSpike` — explicit
    regression test: with `maxOracleDeviationBps = 0` (pre-fix state),
    the adversarial spike is accepted (the bug).
- **Suite impact:** 15 new tests in `TwapCheck.t.sol` + 2 new fuzz tests in
  `SpotVaultNavMonotonicity.fuzz.t.sol`. Full Foundry suite passes
  411/0/1 (was 394/0/1 post-Q8, +17 new tests).
- **Audit gate:** high — pricing model change at the vault level.

### Q10 — [0.A.2] No per-depositor high-water-mark equalization
- **Risk:** late depositors retroactively taxed on gains they never received.
- **File:** `BaseVault.sol` (`evaluateFees` / HWM logic).
- **Fix shape:** track per-share HWM in addition to global HWM; on each
  `deposit()`, snapshot the incoming share's HWM and use it for the
  per-depositor calculation.
- **Test:** `contracts/test/vaults/PerDepositorHWM.t.sol` — first depositor at
  NAV 1.0; second depositor at NAV 1.5; trigger HWM update; observe first
  depositor's fee is on 1.0→1.5 not 1.0→1.5 over both depositors.
- **Audit gate:** high — fee accounting change.

### Q11 — [0.A.3] zBTC/zETH/zSOL/zXRP cannot execute strategy yet charge 20% perf fee
- **Risk:** indefensible in diligence AND to regulators.
- **Current state:** SpotVault v2 has the executor; legacy z-vaults need
  either deprecation or live execution.
- **Decision required (founder):** deprecate or wire to SpotVault v2?
- **Test:** depends on the decision.
- **Audit gate:** depends on the decision.

### Q12 — [0.F.1] Investor-facing backtest ≠ deployed strategy
- **File:** `zentorylabs.com/lib/backtest.ts`.
- **Fix shape:** either (a) update the backtest to use the deployed
  ensemble+hysteresis model (per the `// TODO (owner: research)` at line 35),
  or (b) clearly mark the displayed numbers as "BTC/ETH/SOL/XRP walk-forward,
  not the deployed strategy" with a footnote linking to the deployed ensemble
  description.
- **Test:** none (marketing site, not contract).
- **Audit gate:** low — but high investor-perception impact.

### Q13 — [0.F.2] Public fee-split figures contradict deployed `FeeDistributor` in 3 places
- **Files:** `docs/whitepaper.md` §6.1, `zentorylabs.com/app/tokenomics/page.tsx`,
  `zentorylabs.com/app/pitch-deck/page.tsx`.
- **Fix shape:** normalize all three to the on-chain `FeeDistributor`
  constants (50% buyback/burn · 25% Protocol Treasury · 15% Insurance · 10%
  Ops/GP engine).
- **Audit gate:** low — but diligence will catch it.

### Q14 — [0.F.3] "Recording live — day N" never compared to now
- **File:** `zentorylabs.com/components/TrackRecordDay.tsx` (currently
  hardcodes 2026-06-08 start).
- **Fix shape:** compute start from the actual first bar in
  `/forward_ledger.jsonl`; compare `Date.now() - lastBar` and clamp to 90
  days; show "stale — day N" badge if `now - lastBar > 9h`.
- **Test:** none (marketing site).
- **Audit gate:** low.

### Q15 — [0.D.2] Waitlist + subscriber RLS review
- **File:** `zentory-app/supabase/schema.sql`.
- **Fix shape:** explicit review of `whitelist` and `subscriptions` tables.
  Verify the current RLS lockdown (PR #276) covers all reads/writes; add an
  explicit assertion in the schema postlude.
- **Test:** add a row to `supabase/migrations/` that asserts the RLS posture
  hasn't regressed.
- **Audit gate:** low.

### Q16 — [0.D.3] Contributor API-key expiry
- **File:** `zentory-app/supabase/schema.sql` (`api_keys` table).
- **Fix shape:** add `expires_at` column; API route validates; rotating
  cron-style nudge for users.
- **Test:** add a unit test for the expiry check.
- **Audit gate:** low.

### Q17 — [0.D.1] Tamper-evident ledger has no enforced verifier
- **File:** `zentory-engine/ledger_guard.py` + the keeper cron wrappers.
- **Current state:** `ledger_guard.py` ships (PR #18); single-leader EIP-712
  enforcement in flight.
- **Test:** network-free unit test that constructs an attacker-tampered ledger
  and asserts the keeper refuses to rebalance.
- **Audit gate:** medium.

---

## What needs to happen before this queue starts

1. External audit engaged (Tier 1 #3 in `MAINNET_READINESS.md`).
2. `AUDIT_FINDINGS_2026-08-07.md` file authored with per-finding detail (D.2 in
   the go-to-market checklist).
3. Multisig migration (Tier 1 #2) — without this, the deployer EOA is still
   admin and any fix can be reverted by the same key.
4. Tier 0.5 ops (rotate `GITHUB_TOKEN`, alerts to human channel) — without
   this, the fix might ship but no one notices it's broken in production.

## Estimated engineering effort

- ~6 weeks engineering across all 17 items, with Q1 (ve-supply decay) being
  the longest single item at ~2 weeks.
- Each item is a separate PR; do not batch.
- Run the full Foundry suite (`forge test`) before and after each PR.

---

*Author: Phase E prep · Branch `phase-e/tier-0-prep` · 2026-08-20*
