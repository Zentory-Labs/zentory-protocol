# ZENTORY Roadmap — Resequenced (vault-first → marketplace → token)

This roadmap **replaces** the prior "launch everything" framing. Sequencing
matters more than scope: the protocol's only existential risk is *no proven
alpha*, and the only way to retire it is forward — on a single vault, in public,
for long enough that the track record is real. Token + marketplace come *after*
that, because they depend on it.

Each phase has explicit **GO GATES**. Do not begin a phase until the prior
phase's gates are met. Skipping a gate to chase momentum is what kills protocols.

---

## Phase 1 — House Vault on Testnet (NOW → ~3 months)

Goal: a single, transparent, non-custodial vault running the validated house
strategy on testnet, with on-chain HOLD/GHOST/ACTUAL attribution.
**This is the only phase that matters until it's done.**

What's already built (don't rebuild it):
- Validated long/flat ensemble (turnover-controlled, funding-checked) ✅
- Autonomous forward signal recorder (hourly, tamper-evident hash chain) ✅
- `SpotVault` v2 — NAV reflects strategy PnL (oracle-hardened) ✅
- Ghost Portfolio (#69) attribution engine ✅
- Shadow-stack testnet contracts (one-click deploy) ✅
- Engine signing chain (dry-run) ✅
- 257/258 tests passing across the protocol; 39/40 in the engine.

Phase 1 work (operator + small dev tasks):
1. **Collapse to ONE vault — zBTC.** Pause/defer zETH, zSOL, zXRP. Four empty
   vaults is four cold-starts.
2. **Deploy the shadow stack on testnet** (`deploy-shadow-stack.ps1` →
   `deploy-spot-vault.ps1`, grant VAULT_ROLE, fund reserves).
3. **Wire the keeper to push prices + drive rebalances** every 4H from the
   deployed (hysteresis) signal. The recorder + signing chain are ready; only
   the keeper config needs to point at the new vault + oracle.
4. **Build the Ghost Portfolio tile in the dApp** — surface HOLD/GHOST/ACTUAL
   per share, on the zBTC vault page. The engine computes it; the dApp
   visualises it.
5. **Multisig migration off the leaked deployer EOA.** This is testnet-blocking
   only if you advertise externally; it is mainnet-gating absolutely.
6. **Secrets off OneDrive; paid RPC; real DB.** Audit F-02. Hobby-grade infra
   is fine until you take public deposits — not after.
7. **Run for ≥ 3 months.** This is non-negotiable. Track records are minted in
   wall-clock time, not by writing more code.

### GO GATE for Phase 2 (all four must be true)
- [ ] zBTC has ≥ 3 months of continuous on-chain operation.
- [ ] Ghost Portfolio shows **signal alpha > 0** (GHOST > HOLD in the
      underlying) over the full operating window, after costs.
- [ ] No critical security incidents; no oracle/keeper outages > 24h.
- [ ] External audit booked or complete; legal opinion on ZENT in hand.

If any of these fail, **stay in Phase 1**. There is no Phase 2 without them.

---

## Phase 2 — Open the Signal Marketplace (~Phase 1 + 3–6 months)

Goal: prove the marketplace thesis. Onboard 5–10 hand-picked external quants
who post signals to `SignalRegistry`. Their `GHOST` lines are published; their
`ACCURACY × CONVICTION` ranks are scored by `EpochScoring`. NO TOKEN YET.

Work:
1. Tester sandbox (see `TESTER_SANDBOX.md`) for the first quant cohort.
2. Per-provider Ghost Portfolio — every quant's signal stream gets its own
   HOLD/GHOST line on the leaderboard.
3. `manual_provider` stays the bridge until a quant earns their own signer
   (gated by demonstrated accuracy, not pay-to-play).
4. Insurance fund seed (#102) before scaled deposits.
5. Discovery layer in the dApp — quant profiles, signal feeds, sortable
   leaderboard.

### GO GATE for Phase 3 (all must be true)
- [ ] ≥ 3 external quants posting real signals for ≥ 60 days.
- [ ] Aggregate GHOST > HOLD on the marketplace over the window.
- [ ] Audit complete + remediation done. Multisig live. Secrets posture clean.
- [ ] Legal opinion on ZENT delivered and the FAQ/whitepaper match it (see
      `INVESTOR_FAQ.md` §"Why does anyone use this?" — already fixed to
      utility-safe language).
- [ ] Paid RPC, real DB, monitoring, Immunefi bounty (#97) live.

---

## Phase 3 — ZENT Token + Mainnet (~Phase 2 + 3 months)

Goal: launch ZENT only when buyback-burn has actual fee revenue to consume
and the legal/securities posture is clean.

Work:
1. Mainnet deploy of the audited stack (vaults, signal network, fee router).
2. TGE structure finalized at ≤ 5–8% float (#99). No retroactive farming
   designed to look like profit distribution.
3. `ZENTBuyback` contract auto-triggered by fee accumulation, NOT
   governance-discretion (per `BUYBACK_DESIGN.md` design rationale).
4. Liquidity strategy (#100), governance go-live.
5. Subscription tiers + `ModelBonding` activate only after Phase 2 demand exists.

### Do NOT do at TGE
- Pre-mine speculative airdrop campaigns that frame buyback-burn as a return.
- Any marketing copy that says ZENT holders "earn", "share in", or "benefit
  from" protocol fees. (See `BUYBACK_DESIGN.md` §"Howey").
- Multiple vaults launching simultaneously before Phase 2 has multi-quant
  flow proven.

---

## What this roadmap explicitly defers / cuts

- **Three of four vaults** until Phase 2 (zETH/zSOL probably; zXRP only as
  drawdown-protection per the strategy analysis).
- **SubscriptionVault** until Phase 2.
- **Token + buyback-burn flywheel marketing** until Phase 3, with utility-safe
  language only.
- **Full on-chain governance (Timelock + Zentroller + ZentGovernor)** — keep
  the multisig through Phase 2; on-chain governance is a Phase 3 concern.
- **ModelBonding** — Phase 3, only if there's a model economy worth bonding
  against (almost certainly not for 12+ months).

---

## The single highest-leverage move on the board

Phase 1 step 7 — **time in market for the house vault.** Everything else
follows. Every other "what if we…" decision should be checked against:
*does this accelerate or delay the house vault's track record?*
If it delays, defer it.

The strategy is built. The contracts are built. The attribution is built.
The shadow stack is one click. The bottleneck from here is calendar time
and operational discipline, not engineering.
