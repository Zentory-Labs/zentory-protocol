# ZENTORY — Road to Real Funds & Investors

> **Note:** This document was previously maintained at the monorepo root
> (`ZENTORY LABS/MAINNET_READINESS.md`) but lived outside any git repo, so
> updates couldn't be reviewed. As of 2026-08-14 it now also lives here at
> `zentory-protocol/docs/MAINNET_READINESS.md` (this file). Going forward
> edit this copy in-tree. Tier 0 was re-scored against current `main` on
> 2026-08-14 by the P1-6 branch (`docs/rescore-mainnet-readiness-tier-0`).


**Status 2026-08-07: NOT ready to hold real funds. Stay on testnet.**
Supersedes the 2026-07-10 version: a 54-agent adversarial audit ([AUDIT_FINDINGS_2026-08-07.md](AUDIT_FINDINGS_2026-08-07.md))
found **2 critical + 28 high + 15 medium verified defects, 41 of them mainnet-blocking** — so the
blocker list is no longer just capital and process, it is **code**.

The good news is unchanged: the *product loop* works end-to-end on testnet (signal → keeper →
on-chain rebalance → indexer → dApp). Nothing here says the idea is broken. It says the
implementation is not yet safe to put strangers' money into, and we now know exactly why.

Legend — **Owner:** F=founder · E=engineering · X=external · L=legal.
**Cost:** 2026 USD. **Status:** 🔴 not started · 🟡 in progress · 🟢 done.

---

## TIER 0 — Code defects. Fix before ANY real deposit.

Full detail per item in [AUDIT_FINDINGS_2026-08-07.md](AUDIT_FINDINGS_2026-08-07.md). Grouped by theme,
because these are six systemic problems, not 46 unrelated bugs.

### 0.A Vault fee/NAV machinery — the most dangerous code in the repo
| Item | Why it blocks funds | Owner | Status |
|---|---|---|---|
| **CRITICAL: `SpotVault.totalAssets()` clamps to 0** → the next dust depositor mints ~10,000× the entire supply and drains the vault. **Proven with a passing Foundry PoC** ([`docs/security/poc/SpotVaultPinPoc.t.sol`](security/poc/SpotVaultPinPoc.t.sol)): attacker pays ~$2.75, redeems 5,230× while honest depositors lose ~100% of principal. | Total loss of all depositor principal, by an unprivileged attacker, reachable after any large exit + a small adverse tick. | E | 🟢 closed (PR #56, `729d898`) |
| Performance fees accrue into a **one-way sink** — SpotVault has no `claimFees()`, so accrued only ever grows and is the mechanism that drives the critical above. | Fees are unwithdrawable AND they ratchet the vault toward the critical state. | E | 🟢 closed (BaseVault `claimFees()` and SpotVault `claimFees()` both present on main; PR #56 + PR #53, `0f36493` added the admin-settable fee recipient) |
| Stale-price window lets a depositor/redeemer extract mispricing from everyone else. | Value transfer between users; classic oracle-latency arbitrage. | E | 🔴 |
| No per-depositor high-water-mark equalization. | Late depositors are retroactively taxed on gains they never received. | E | 🟢 closed (Q10 fix on `fix/0-a-10-hwm-equalization`; per-depositor HWM via OZ fee-share dilution + atomic `_captureFee` on every deposit/withdraw + permissionless `evaluateFees()`; regression at `contracts/test/vaults/PerDepositorHWM.t.sol` with 13 tests, full suite 396/0/1). |
| **`zBTC/zETH/zSOL/zXRP` cannot execute the strategy at all — yet charge a 20% performance fee and advertise "3x".** | Charging a performance fee for a strategy that cannot run is the single most indefensible thing here in diligence *and* to a regulator. | F+E | 🟢 closed — decision: deprecate (see `docs/decisions/2026-08-21-q11-zvaults-deprecate.md`). Active surface: legacy z-vaults get the existing `BaseVault.activateCircuitBreaker(reason)` via `script/PauseZVaults.s.sol` (founder-key broadcast remains the one open step). Future pattern locked in source: `src/vaults/PassiveVault.sol` with `performanceFee=0, maxLeverage=0`, so this class of bug cannot recur on a new deploy. 14 regression tests in `test/vaults/ZVaultDeprecation.t.sol` (CB-blocks-deposit + withdraw-still-works per legacy vault, PassiveVault constructor invariants). Invariant `test/invariants/BaseVaultNavMonotonicity.inv.t.sol` (NAV-per-share is invariant under passive-vault no-op surface, 256 runs / 128K calls). |
| Oracle going quiet freezes **all** withdrawals; no fallback, no admin override. | Users cannot exit. "Can't withdraw" ends a protocol. | E | 🟡 partial — MedianOracle (`e4ac913`) gives redundancy across venues; admin override still missing. |

### 0.B Signal/scoring economy — not safe to run with money attached
| Item | Why | Owner | Status |
|---|---|---|---|
| **CRITICAL: `applyPayout()` has no idempotency** — re-runnable per `signalId` → repeatable slash / unlimited reward mint. | Anyone can drain the reward path or repeatedly slash a provider's bond. | E | 🟢 closed (PR #56, `729d898` — `payoutApplied[signalId]` guard at `EpochScoring.sol:431-432`) |
| `accuracyCache` defaults to `0`, and **0 is the maximum-slash input** — an unscored signal is indistinguishable from a maximally-wrong one. | A dead scoring oracle silently burns every provider's stake. | E | 🔴 |
| O(n²) sort + ~10 external calls per signal over an attacker-growable list. | Permanent gas DoS of epoch settlement. | E | 🔴 |
| Reward payouts **silently never execute** (no ERC-20 allowance is ever granted; revert is swallowed). | Providers get slashed but never paid — the incentive model is inverted in production. | E | 🔴 |
| A single hot-key EOA sets arbitrary, overwritable, unverified accuracy that drives real payouts. | One key compromise rewrites the entire performance record. | F+E | 🔴 |

### 0.C Governance & staking accounting
| Item | Why | Owner | Status |
|---|---|---|---|
| **`totalVeSupply` ratchets up forever → governance bricks permanently.** *Verified mechanism (sharper than the audit's wording):* `withdraw()` requires `block.timestamp >= pos.lockEnd` (ZENTStaking.sol:159), but `_veAt()` returns **0** once `at >= lockEnd` (:185) — so `totalVeSupply -= oldVe` (:164) **always subtracts zero**. The total is incremented at stake time, never decremented, and never decays, while every individual `veBalance()` decays to 0. `ZentGovernor.quorum = totalVeSupply * quorumBps / 10000` therefore becomes unreachable. | Governance permanently un-passable, and **irreversible** once it happens (you cannot vote to fix voting). | E+F | 🔴 |
| ⚠️ **Deliberately NOT auto-fixed** — the repair is a ve-accounting redesign (Curve-style checkpointed slope decay) **or** a semantics change (base quorum on `totalStaked`, which *is* maintained correctly). That is a tokenomics decision, not a bug patch; a rushed rewrite here is more dangerous than the bug. Needs a founder decision + the external auditor. | — | F+X | 🔴 |
| Governor reads **live** state instead of the proposal snapshot. | Any proposal can be defeated/manipulated after the fact. | E | 🔴 |
| Slashed ZENT is permanently unrecoverable (`insuranceFund` defaults to the staking contract itself). | Real value burned into a black hole. | E | 🔴 |

### 0.D Off-chain trust boundaries
| Item | Why | Owner | Status |
|---|---|---|---|
| **Keepers take real-money rebalance commands from an unauthenticated public text file**, with no freshness or signature check. | Anyone who can influence that file can move the vault. This is the off-chain equivalent of a missing `onlyRole`. | E | 🟢 closed (zentory-engine PR #17, `f88c4f7` — `ledger_guard.py` enforces EIP-712 + chain-id; signed rebalance commands are now authenticated end-to-end) |
| The tamper-evident ledger has **no enforced verifier** — `verify_ledger()`'s result is discarded. | The "verifiable track record" is not actually enforced anywhere. | E | 🟡 partial — `ledger_guard.py` ships and is invoked by the keepers (PR #17), but not every rebalance cron yet imports it. Leader-bound (single-leader) EIP-712 enforcement still in flight. |
| One keeper key drives three colliding crons → nonce collision silently drops real rebalances. | Strategy silently doesn't trade. | E | 🟢 closed (zentory-engine PR #17 — nonces are now derived from the EIP-712 payload, separate per keeper path) |
| Oracle price pushed from the first single venue that answers; no median, no deviation guard. | One bad venue print moves NAV. | E | 🟢 closed (MedianOracle PR #40, `e4ac913`) |

### 0.E Data plane is world-writable *(verified directly in `supabase/schema.sql`)*
| Item | Why | Owner | Status |
|---|---|---|---|
| Public anon key has **unrestricted INSERT/UPDATE** on `signals`, `provider_stats`, `profiles`, `keeper_audit` (`using (true)` policies named "…_keeper" that restrict nothing). | Anyone can forge or rewrite the data behind the track record — it destroys the core "verifiable" claim. | E | 🟢 closed (zentory-app PR #276, `b3bcf99` — `2026-08-07_lock_down_rls.sql` tightens policies; service-role writes only via backend) |
| Waitlist emails + subscriber records world-readable with the anon key. | Personal-data exposure (GDPR relevance given EU ambitions). | F+E | 🟡 partial — RLS lockdown reduced the public surface; an explicit waitlist-table RLS review still owed. |
| Contributor API keys never expire, self-replicate, validated against a table absent from the schema. | Broken auth on the contributor surface. | E | 🟡 partial — `/contribute` dead-end fix (zentory-app PR #275, `d9f8142`) unified API-key storage; expiry/expiry-policy audit still pending. |

### 0.F Public claims vs. reality *(what diligence will actually catch)*
| Item | Why | Owner | Status |
|---|---|---|---|
| The investor-facing backtest table **describes a different strategy than the deployed one**. | This is the finding that ends a raise. Must be reconciled before any deck goes out. | F | 🔴 |
| Public fee-split figures contradict the deployed `FeeDistributor` in **three** places. | Whitepaper-vs-code diff is the first thing a technical investor runs. | F | 🔴 |
| "Recording live — day N" is computed from the ledger's own first/last bar and **never compared to now**. | This is precisely why the site kept showing "live" through a 30-day data outage (below). | E | 🔴 |

---

## TIER 0.5 — Operational maturity (the lesson that cost 30 days)

On 2026-08-07 the public forward track record was found **frozen for 30 days** (last entry
2026-07-08). Root causes: an expired `GITHUB_TOKEN`, a **deleted Railway volume**, and — the real
one — a health monitor that detected it correctly and alerted **no human** for a month while
benign NAV flapping trained everyone to ignore the channel.

**Nothing on this list is optional for a protocol holding other people's money.** A perfect
contract that nobody notices has stopped is still a loss.

| # | Item | Owner | Status |
|---|---|---|---|
| 1 | Rotate `GITHUB_TOKEN` (contents+PR write on `zentory-app`) — publishing stays frozen until then. **Do not paste it in chat.** | F | 🔴 still open — pending founder action |
| 2 | Railway volume re-attached (`zent-recorder-volume` → `/app/forward`) so unpublished bars survive as a retryable backlog. | E | 🟢 |
| 3 | Credential-expiry + volume-loss now shout in the logs ([engine #15](https://github.com/Zentory-Labs/zentory-engine/pull/15)). | E | 🟢 |
| 4 | Alert thresholds retuned to 2× cadence so real alarms aren't buried in flapping ([engine #16](https://github.com/Zentory-Labs/zentory-engine/pull/16)). | E | 🟢 |
| 5 | **Route alerts to a channel you actually read** (email/SMS/push), alert on *state change* + escalate on duration, not every 30 min. | F | 🔴 — Discord channel confirmation (P1-2) still pending |
| 6 | Decide the 30-day gap: **recommendation — disclose it, do NOT backfill.** A forward record's value is that it was committed *at the time*; a bulk backfill is detectable and reads as fabrication. The hash chain stays intact across the gap. | F | 🔴 — founder call still owed |
| 7 | Inventory every credential with an expiry + owner + rotation date. This class of failure will otherwise recur. | E+F | 🟡 partial — `.env`-off-OneDrive plan + rotation policy docs exist; rotation calendar not yet enforced |
| 8 | Make staleness **publicly visible** (dApp shows true age vs now), so an outage can never look "live". | E | 🟢 closed (zentory-app PR #276 — staleness gate, "live" claim removed when publishing has stalled) |

---

## TIER 1 — Hard gates (mainnet without these is negligent)

| # | Item | Owner | Cost | Status |
|---|---|---|---|---|
| 1 | **Fresh keys on hardware wallets.** The current deployer/admin key was leaked in chat — deploying with it means compromised-from-block-1. Never reuse `0xdc42895e…` / `0xe56E…`. | F | ~$300 | 🔴 |
| 2 | **Safe → 2-of-3 on hardware signers.** Today: 3-of-3 hot keys on one machine (one compromise drains; one lost key locks forever). | F | gas | 🔴 |
| 3 | **External audit** — after Tier 0 is fixed, so you don't pay audit rates for bugs we already found. Longest lead item. | X | **$40k–150k** | 🔴 |
| 4 | Audit remediation + re-review. | E→X | in fee | 🔴 |
| 5 | **Legal: token-classification opinion + operating entity** (also the precondition for un-blocking US/EU). | L/F | **$15k–60k** | 🔴 |

## TIER 2 — Mainnet-shaping engineering (no capital needed — do during the audit)
| # | Item | Owner | Status |
|---|---|---|---|
| 6 | De-pin from testnet: chain-998 defaults, hardcoded testnet addresses across 18 files, no chain-keyed registry. | E | 🔴 |
| 7 | Fee-recipient setters: SpotVault ✅ ([protocol #53](https://github.com/Zentory-Labs/zentory-protocol/pull/53), awaiting your review); `SubscriptionVault.treasury` still immutable **and** has no access-control model — a governance decision, see [FEE_CONSOLIDATION_PLAN.md](FEE_CONSOLIDATION_PLAN.md). | E+F | 🟡 |
| 8 | ≥3 independent oracle updaters (single updater = single point of price manipulation). | F+E | 🔴 |
| 9 | Fee routing → treasury Safe. Blocked on: Safe deployed on the target chain, the all-vs-treasury-leg decision, admin key. | F+E | 🟡 |
| 10 | Paid dedicated RPC (a free public endpoint is fine for testnet, not for mainnet volume). | E+F | 🔴 |

## TIER 3 — Launch scaffolding (capital-gated)
| # | Item | Cost | Status |
|---|---|---|---|
| 11 | Seed DEX liquidity + market maker | $30k–150k POL + MM | 🔴 |
| 12 | Insurance fund seed (the drawdown-protection thesis needs a real backstop) | $10k–50k | 🔴 |
| 13 | Public bug bounty (Immunefi) | $10k–50k pool | 🔴 |
| 14 | Listings (DEX ≈ free; skip CEX at launch) | $0–100k+ | 🔴 |
| 15 | Marketing / KOL / launch PR | $10k–100k+ | 🔴 |

## TIER 4 — Time & capital
| # | Item | Status |
|---|---|---|
| 16 | **~90-day continuous live track record.** Clock started ~June 2026 but **lost 30 days** to the outage — treat the resumed record as the real clock. | 🟡 restarting |
| 17 | **Raise.** Funds #3, #5, #11–15. Going to mainnet before raising is backwards: you can't afford the audit and liquidity that make mainnet safe. [FUNDRAISING_PLAYBOOK.md](FUNDRAISING_PLAYBOOK.md) | 🔴 |

---

## Cost to launch
- **Lean:** ~**$90k–200k** (one mid-tier audit, offshore entity, modest POL, no CEX, minimal MM)
- **Standard:** ~**$250k–600k** (top-tier/multiple audits, fuller legal, deeper liquidity + MM retainer, marketing)

## The sequence that is actually best

```
NOW  ── TIER 0 code fixes (criticals first: SpotVault clamp, applyPayout replay, RLS write-open)
      ├─ TIER 0.5 ops: rotate the token, fix alert routing, disclose the gap
      ├─ TIER 0.F reconcile every public claim with the code   <-- do BEFORE any investor sees a deck
      └─ TIER 2 mainnet-shaping (free, and it lands in the codebase the auditor reads)
            │
            ▼
   #16 let the 90-day record run clean on the fixed system   (calendar time — start it now)
            │
   #17 RAISE ──► unlocks:
            ├─ #3 external audit ──► #4 remediation      (longest pole, months)
            ├─ #5 legal opinion + entity                 (parallel)
            └─ #1/#2 fresh hardware keys + real 2-of-3 Safe   (cheap, do this week regardless)
                  │
                  ▼  audit passed + 90 clean days + funded
            #9 fee routing · #11 liquidity+MM · #12 insurance · #13 bounty · #10 paid RPC
                  │
                  ▼
              MAINNET (fresh keys, de-pinned scripts) ──► #14 listings ──► #15 launch ──► TGE
```

**Realistic target: Q1–Q2 2027.** That is later than the old estimate for one honest reason —
Tier 0 didn't exist before we looked, and it must be fixed *before* the audit to be worth paying for.

**The five things you cannot skip:** Tier 0 criticals · external audit · legal opinion ·
fresh keys + real multisig · a 90-day record on the *fixed* system.

**The cheapest, highest-value thing you can do this week:** reconcile the public claims (0.F) and
rotate the token (0.5 #1). Both are free, and the first is the one that would otherwise end a raise.
