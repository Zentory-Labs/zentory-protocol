# ZENTORY Labs — Fundraising Playbook

> Referenced by `MAINNET_READINESS.md` Tier 4 #17. Source content: `docs/INVESTOR_ONE_PAGER.md`, `docs/INVESTOR_FAQ.md`, `docs/TGE_STRUCTURE.md`, `docs/LEGAL_COUNSEL_SHORTLIST.md`.

This playbook exists so the team does not improvise the raise under time pressure. The numbers below come from `MAINNET_READINESS.md` Tier 3 (capital-gated launch scaffolding) and the working allocation in `TGE_STRUCTURE.md`. The mechanics (SAFE, token warrants, equity in the operating entity) come from how comparable protocols have structured their seed → TGE rounds without triggering securities issues.

The headline frame is the same as in `INVESTOR_ONE_PAGER.md` and `INVESTOR_FAQ.md`: **selective strategic round, not a public fundraise, no CMS-public raise, no general public solicitation.** Term-sheet specifics remain under NDA and are not duplicated here.

---

## 1. Capital Plan Summary

These are the Tier 3 items from `MAINNET_READINESS.md`, expressed as the working budget for the raise. Numbers are the published band; the actual commitment depends on what clears Tier 0 (code defects) and Tier 0.5 (operational maturity) before any external capital is touched.

| Category | Budget band (USD) | Purpose | Tier 3 # | Funding source |
|---|---|---|---|---|
| **Seed DEX liquidity + market maker** | $30k – $150k | Initial POL on HyperSwap ($ZENT side locked 12mo per `TGE_STRUCTURE.md`) + MM retainer | #11 | Strategic round + ecosystem grants |
| **Insurance fund seed** | $10k – $50k | Drawdown-protection backstop; see `BUYBACK_DESIGN.md` for the 15% insurance slice feeding it post-TGE | #12 | Strategic round |
| **Public bug bounty (Immunefi)** | $10k – $50k | Bounty pool size; `docs/IMMUNEFI_SETUP.md` is the operational doc | #13 | Strategic round |
| **Marketing / KOL / launch PR** | $10k – $100k+ | Pre-TGE KOL seeding, Tier-2/3 crypto press, launch week | #15 | Strategic round |
| (Pass-through) **External audit** | $40k – $150k | Tier 1 #3; gated on Tier 0 being closed first | — | Strategic round |
| (Pass-through) **Legal opinion + entity** | $15k – $60k | Tier 1 #5; see `LEGAL_COUNSEL_SHORTLIST.md` | — | Strategic round |

### Total band

- **Lean:** ~$90k – $200k (one mid-tier audit, offshore entity, modest POL, no CEX, minimal MM).
- **Standard:** ~$250k – $600k (top-tier/multiple audits, fuller legal, deeper liquidity + MM retainer, marketing).

These match `MAINNET_READINESS.md` §"Cost to launch." The seed round sized in `INVESTOR_ONE_PAGER.md` is **$1.5M**, which clears both bands with margin for unexpected Tier 0/0.5 remediation work or an audit re-review (Investor FAQ worst-case #1: $50–100k extra).

### Use-of-funds framing for the deck

From `INVESTOR_ONE_PAGER.md`:

| Category | Allocation | Purpose |
|---|---|---|
| Protocol development | 40% | Ghost Portfolio engine, Auto-Follow contracts, ZENTORY Score, audit |
| Growth & ecosystem | 30% | Quant contributor acquisition, KOL partnerships, Vault TVL incentives |
| Legal & compliance | 20% | Token legal opinion, geo-blocking, jurisdiction mapping |
| Operations | 10% | Infrastructure, team |

---

## 2. Funding Vehicles

The vehicle mix depends on what the lead investor is willing to clear. The default plan below minimises securities friction and keeps the TGE schedule (`TGE_STRUCTURE.md`) intact.

### 2.1 SAFE (Simple Agreement for Future Equity) into the operating entity

**When to use:** US-blocked launch, BVI/Cayman/Singapore entity recommended by `LEGAL_COUNSEL_SHORTLIST.md`, lead investor is crypto-native and comfortable with a SAFE → equity-at-TGE conversion.

- Cheapest, fastest paperwork.
- Discount + valuation cap negotiated per investor; standard 20–30% discount, $20–40M cap for a seed of this size.
- Conversion triggers: equity financing above the cap, change of control, or liquidity event (TGE does not auto-trigger — the operating entity and the token are separate assets).
- MFN clause for non-leads.

**Risk:** the SAFE converts into equity in the operating entity at some future event; the TGE raises capital into the protocol/treasury, not the operating entity. The investor gets a piece of the operating entity's revenue (e.g., professional services fees from the foundation, if any) — **not** a piece of the protocol's on-chain revenue. The deck must say this out loud. This is consistent with the FAQ's "What is the moat?" framing: ZENT holders have no claim on protocol revenue, and the SAFE investor's claim is on the operating entity, not on ZENT.

### 2.2 Token warrants (or token-side SAFT)

**When to use:** investor wants economic exposure to ZENT specifically; investor is comfortable with a token warrant at a fixed strike against the published TGE schedule.

- Token warrant grants the right to purchase a fixed ZENT allocation at TGE at a strike price set at signing.
- Allocation comes out of the **Strategic round** bucket (10% / 100M ZENT per `TGE_STRUCTURE.md`).
- Vesting mirrors the published strategic-round schedule (18-month linear, 6-month cliff) — *do not* negotiate faster vesting without re-balancing the published schedule; it changes the float math.
- Jurisdiction-sensitive: a token warrant is a forward contract on a token that may be classified as a security in some jurisdictions. Requires the legal opinion from §5 to land first.

### 2.3 Equity in the operating entity (priced round)

**When to use:** lead investor requires equity, or the raise is large enough that a priced round is cheaper than a stack of SAFEs.

- Priced equity into the operating entity (Delaware C-corp or Cayman/BVI/Singapore entity per `LEGAL_COUNSEL_SHORTLIST.md`).
- Standard seed terms: $1.5M at a $15M post-money cap, 1× non-participating preference, standard pro-rata, broad-based weighted-average anti-dilution.
- Board seat or observer right for the lead.
- This is the most paperwork-heavy option; budget 4–6 weeks of legal time on top of the entity setup.

### 2.4 Recommended default

For ZENTORY's stage and capital needs, the recommended default is **SAFE into the operating entity for the cash needs, plus a small token warrant allocation for ecosystem partners who want protocol-aligned exposure.** This mirrors how comparable HyperEVM-native protocols have raised without compromising the `TGE_STRUCTURE.md` float math.

---

## 3. Lead Investor Targets

We are not running a public fundraise, so lead investor selection is a deliberate funnel — not a "whoever says yes wins" race. Priorities, in order:

1. **Strategic capital with HyperEVM ecosystem reach.** Native to the chain the protocol lives on. They can intros to other protocols, list us in their ecosystem decks, and have an honest reason to care about the protocol's success.
2. **Audit-firm and legal-counsel intros.** A lead who already has Spearbit / Cantina / Zellic / Cooley / Lex Crypta relationships saves us 2–4 weeks of calendar.
3. **Tier-1 LP intros for post-mainnet deposit ramp.** Once vaults are live, having the lead's portfolio of institutional LPs pre-warmed for the first deposit tranche is materially more valuable than a small bump in the round size.
4. **Crypto-native VCs with public track records.** Vetted for fund reputation, follow-on behaviour, and absence of predatory terms. We vet investors as carefully as they vet us, per the FAQ.

Firms that have explicitly engaged with HyperEVM ecosystem capital or that have publicly backed comparable protocols (DeFi vaults, signal markets, reputation primitives) are the priority outreach. Cold outreach to generalist VCs is a fallback, not the primary motion.

### What we will not optimise for

- Highest valuation. A higher valuation now means a flatter option pool later and a worse conversion ratio at the next round; for a protocol whose value is the next 18 months of execution, not a single headline number.
- Brand-name leads who will not engage with the protocol after the wire clears. The post-TGE relationship is more valuable than the pre-TGE signal.
- Anyone who conditions capital on terms that change the published TGE schedule (founder vesting, treasury discretion, fee split governance). Those numbers are public; changing them underwriter pressure reads as governance capture.

---

## 4. Pre-TGE Checklist

The TGE schedule is **gated**, not promised — the gate is in `TGE_STRUCTURE.md` and `MAINNET_READINESS.md`. Items below are the *capital side* of that gate.

### 4.1 Legal

- [ ] **Legal entity live.** BVI/Cayman/Singapore entity incorporated with a functioning bank account or stablecoin treasury address. `docs/LEGAL_COUNSEL_SHORTLIST.md` is the intake list; engagement letter signed with the chosen firm.
- [ ] **Token-classification opinion received.** US (Howey), EU (MiCA), Singapore (SFA) coverage at minimum. Opinion must address: ZENT utility classification, the no-revenue-share structure, the geographic blocking strategy, the quant-rewards-as-treasury-grants framing.
- [ ] **ToS + Privacy Policy reviewed and published.** Crypto-native pass, not a template pass. Includes risk-disclosure language for the dApp, the marketing site, the whitepaper.
- [ ] **SAFe / token-warrant paperwork executable in the target jurisdictions.** SAFE is jurisdiction-neutral; token warrants require opinion-supported form.

### 4.2 Code and security

- [ ] **Tier 0 criticals closed.** `MAINNET_READINESS.md` Tier 0 — specifically the SpotVault clamp, the `applyPayout` replay, and the RLS write-open. All three are required before any external audit dollar is spent.
- [ ] **External audit engaged and report received.** Spearbit/Cantina/Zellic — see `docs/AUDIT_OUTREACH.md`. Report is shared with lead investors under NDA, redacted for any exploit detail.
- [ ] **Audit remediation complete and re-reviewed.**
- [ ] **Tier 0.5 closed.** `GITHUB_TOKEN` rotated, alert routing moved off Discord-only to email/SMS/push, credential expiry calendar in place. The 30-day outage postmortem (`docs/postmortems/2026-08-07-30-day-recording-outage.md`) action items resolved.
- [ ] **Bug bounty live on Immunefi.** Same day as mainnet, per `docs/IMMUNEFI_SETUP.md`.

### 4.3 Operations

- [ ] **Safe 2-of-3 on hardware signers** deployed on mainnet target chain. `docs/MULTISIG_MIGRATION_PLAN.md` and `docs/KEY_MANAGEMENT.md`.
- [ ] **Fee routing consolidated.** Per `docs/FEE_CONSOLIDATION_PLAN.md`: every `FeeDistributor` points to the Ecosystem Treasury Safe; `SubscriptionVault.treasury` updated.
- [ ] **Forward track record** with at least 90 clean days on the fixed system (Tier 4 #16). The 30-day outage gap is disclosed, not backfilled.
- [ ] **Tier 0.F claims reconciled.** Whitepaper, investor one-pager, marketing site backtest, fee-split, and on-chain reality all agree.

### 4.4 Disclosure and comms

- [ ] **Investor data room live.** Whitepaper, audit report (redacted), key audit findings closed, Tier 0 evidence, Tier 0.5 evidence, cap table, entity docs.
- [ ] **One-pager and FAQ current.** Reflect the post-Tier 0 numbers, the post-FEE_CONSOLIDATION_PLAN fee split, and the post-RLS-lockdown data plane claims.
- [ ] **Disclosure cadence agreed in advance** (see §6).

---

## 5. Post-TGE Runway Extension Mechanics

The raise is sized for the **launch**, not the **first 24 months of operation**. Post-TGE, runway extends through two mechanisms.

### 5.1 Treasury diversification

After the TGE float and the post-launch price discovery window (first 30 days), the protocol treasury holds ZENT, the underlying POL leg (USDC), and any base-asset fees accumulated in the launch window. Diversification policy:

- **Tier 1 (months 1–3 post-TGE):** No diversification. Single-asset treasury is the right posture while the price-discovery is volatile. Documented in `TGE_STRUCTURE.md` cadence.
- **Tier 2 (months 4–12):** Begin converting a measured slice of accumulated protocol fees into stablecoins for operating-expense coverage. Sized to 6–12 months of opex, not more.
- **Tier 3 (month 12+):** Diversification into a basket (BTC, ETH, stablecoins) governed by `ZentGovernor` per the published `TGE_STRUCTURE.md` "What can governance change?" list.

The 15% insurance slice flows into the insurance fund per the same cadence. The 10% ops slice covers operating expenses directly.

### 5.2 Buyback / burn cadence

Per `TGE_STRUCTURE.md` "Buyback + burn cadence": every Friday post-launch:

1. Read accumulated fees from each vault's `FeeDistributor`.
2. Route 50% of the perf fee share into `ZENTBuyback.sol`.
3. Swap the underlying (USDC/WBTC/etc.) for ZENT on HyperSwap.
4. Send bought-back ZENT to `0x000000000000000000000000000000000000dEaD`.
5. Tweet the tx hash + amount.

This is structural deflation tied to actual protocol revenue. The more vault NAV grows, the more ZENT gets burned. The cadence is **predictable, transparent, no governance discretion** — those are the properties that make it a credible runway-extension narrative for the next raise.

### 5.3 What we will not do post-TGE

- No treasury ZENT sales into a falling market for opex coverage. The opex reserve is built first, in stablecoins, before any ZENT-denominated opex is contemplated.
- No discretionary buyback pauses. If the buyback is paused, that is a governance event with a published rationale, not a private decision.
- No fee-split changes. Per `TGE_STRUCTURE.md`, the 50/25/15/10 split is in the "cannot" column for governance — change requires full redeploy + migration, which is the correct gravity for a parameter that defines the deflation thesis.

---

## 6. Disclosure Cadence

We commit to a cadence before the round closes so investors know what they will and will not hear from us, and when.

### 6.1 Pre-TGE (between wire and TGE)

- **Monthly investor update.** Engineering progress, Tier 0/0.5/1 status, audit progress, no marketing claims. Sent to the investor mailing list. No public republication.
- **Material-event updates within 48 hours.** Audit finding, key compromise, regulatory inquiry, schedule slip. Sent to the investor mailing list first; status page second.
- **No forward financial projections.** Pre-revenue protocols that publish projections set themselves up to fail at them.

### 6.2 At and immediately post-TGE

- **TGE day:** public announcement (status page, Twitter/X, blog post), investor email within 24 hours with the same content + the on-chain proof links (POL tx, treasury address, buyback contract address).
- **First 30 days post-TGE:** weekly update on the buyback/burn cadence, the insurance fund balance, the treasury balance, and the vaults (TVL, performance, circuit-breaker state). Public.
- **Month 2–6 post-TGE:** bi-weekly update. Same content as week 1–4.

### 6.3 Steady state (month 6+)

- **Monthly** on-chain transparency report (treasury, insurance, buyback history).
- **Quarterly** written investor update. Includes KPIs the protocol can credibly defend (vault TVL, signal volume, Ghost Portfolio gap, on-chain unique users).
- **Annual** postmortem of the prior year (security incidents, near misses, missed targets, lessons learned). Public, per `docs/INCIDENT_RESPONSE.md` §8.

### 6.4 What is off-cadence

- Anything that affects user fund safety goes out within the SEV0/SEV1 cadence in `INCIDENT_RESPONSE.md`, not the fundraising cadence.
- Anything legal-counsel advises against disclosing (active regulator inquiry, undisclosed exploit) does not get disclosed regardless of cadence.

---

## 7. Anti-Patterns (What We Will Not Do)

Documented explicitly so a future co-founder or advisor does not need to re-derive them:

1. **Will not inflate the round to chase valuation.** Higher valuation now means a flatter option pool later. For a 18-month-execution story, the dilution math matters more than the headline.
2. **Will not take capital from anyone who conditions it on fee-split changes, treasury discretion, or founder-vesting changes.** Those are public commitments to the TGE schedule.
3. **Will not run a public sale before the legal opinion lands.** "Public sale" includes IDO/ICO/IFO structures, public DEX liquidity bootstraps before counsel sign-off, or any general solicitation.
4. **Will not backfill the forward track record.** A bulk backfill is detectable and reads as fabrication. The 30-day outage is disclosed, not hidden.
5. **Will not change the published 50/25/15/10 fee split pre-TGE under investor pressure.** The fee split is part of the deflation thesis; renegotiating it post-term-sheet signals that the thesis is negotiable. It is not.
6. **Will not commit to a TGE date in the term sheet.** The schedule is gated on audit + multisig migration; a date commitment that ignores the gate is a date commitment that will be missed.

---

## 8. Cross-References

- `docs/MAINNET_READINESS.md` — Tier 3 capital items, Tier 4 #17 raise gate, Tier 0/0.5 preconditions.
- `docs/TGE_STRUCTURE.md` — token allocation, vesting, buyback cadence, the fee-split "cannot" list.
- `docs/INVESTOR_ONE_PAGER.md` — the public-facing summary of the same numbers.
- `docs/INVESTOR_FAQ.md` — the question-by-question version of this playbook.
- `docs/LEGAL_COUNSEL_SHORTLIST.md` — counsel intake, entity decisions, opinion scope.
- `docs/MULTISIG_MIGRATION_PLAN.md` — the Safe migration that must precede the fee-routing work in `docs/FEE_CONSOLIDATION_PLAN.md`.
- `docs/BUYBACK_DESIGN.md` — the structural-deflation mechanism this playbook references.
- `docs/INCIDENT_RESPONSE.md` — the SEV0/SEV1 cadence that overrides the fundraising cadence when user funds are at risk.

---

*Last updated: 2026-08-20. Tracked under Phase D of the go-to-market checklist. Pre-TGE document; numbers are working intent, not committed.*
