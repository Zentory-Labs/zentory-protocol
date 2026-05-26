# Investor FAQ

Concise, honest answers to the questions sophisticated investors ask about
DeFi protocols before writing a check. Last updated 2026-05-26.

Public version of the FAQ — for confidential financials and term-sheet
specifics, contact edge@zentorylabs.com directly.

---

## What is ZENTORY in one sentence?

A non-custodial, multi-asset Alpha Vault protocol on Hyperliquid's HyperEVM
that combines ERC-4626 vault infrastructure with an on-chain signal market
where quants stake ZENT against the accuracy of their predictions and get
paid in ZENT when they're right.

## Why now?

Three things converged in the last 12 months:

1. **HyperEVM matured.** $2.8B TVL, 175+ protocols, native order book with
   $5–15B in daily perp volume. We're past the "ghost town" risk window
   that kills new chains.
2. **Custodial copy-trading is structurally broken.** Post-FTX (2022),
   post-Celsius, post-multiple smaller blow-ups, the CFTC + SEC have made
   unverifiable copy-trading legally risky for platforms AND users. There's
   a real market hunger for non-custodial alternatives.
3. **The $2.4B paid-signal market has no honest infrastructure.** Telegram
   channels delete their bad calls, copy-trading platforms custody funds,
   "alpha" claims are screenshots. We're building the on-chain attestation
   layer that the market never had.

## What's the moat?

Not technology — every component (ERC-4626, EIP-712, Merkle distributors)
is open-source. The defensibility comes from network effects in three
layers:

1. **Reputation moat.** Every signal is signed by a wallet and lives
   on-chain forever. A quant who builds a 2-year track record on ZENTORY
   has a portable proof that's expensive to recreate elsewhere.
2. **Liquidity moat.** LP capital concentrates around vaults with proven
   strategies + audited mandates. Once a vault has $X in deposits and a
   12-month track record, switching to a fresh competitor protocol means
   restarting the entire trust loop.
3. **Distribution moat.** Subscription revenue from signal feeds funds
   buyback-burn of ZENT, which compounds for early holders. The flywheel
   is structural, not promotional.

## How does the protocol make money?

20% performance fee on yield generated above each vault's high-water mark,
distributed via the `FeeDistributor` contract. Split is hardcoded:

- 50% → ZENT buyback + burn (continuous deflation tied to actual usage)
- 25% → treasury (governance-controlled)
- 15% → insurance fund
- 10% → ops

Plus subscription revenue: ZENT-denominated paid signal feeds at three
tiers, gated by `SubscriptionVault.sol`. Subscription revenue routes to the
same `FeeDistributor` split.

## What's the TAM?

Three overlapping addressable markets, sized conservatively:

- **DeFi vault TVL** — Yearn + Pendle + DeFi vault categories sit around
  $5B; non-custodial competitors to centralized copy-trading represent a
  much larger latent market
- **Paid signal market** — $2.4B+ annually across Telegram, Discord, and
  copy-trading platforms, mostly unverifiable; ZENTORY is the first
  on-chain attestation layer
- **Quant talent monetization** — Numerai-style competitions have proven
  there's appetite ($300M+ NMR market cap pre-correction); ZENTORY is the
  on-chain equivalent for crypto

We don't claim the whole TAM. We aim for the slice where verifiable
reputation matters: serious quants, sophisticated LPs, treasury-management
desks looking for non-custodial yield.

## Who are the competitors?

- **eToro Copy / Bitget Copy / Bybit Copy** — custodial, the structural
  alternative we replace
- **dHEDGE** — non-custodial but manager-discretion-heavy, no on-chain
  signal accountability
- **Yearn** — non-custodial but no on-chain quant reputation; strategies
  are opaque
- **Hyperliquid native vaults** — non-custodial but a single mandate
  controlled by one operator; no signal market
- **Numerai** — closest comparable for the quant-competition piece but
  off-chain rewards + S&P 500 universe (not crypto)
- **AI agent products (RootAI, etc.)** — chat-based AI agents claiming
  alpha; structurally unverifiable, often custodial. See our blog post
  "Why ZENTORY" for the side-by-side.

No single competitor combines all four pillars (non-custodial vault +
signal market + on-chain reputation + Hyperliquid execution).

## What's the regulatory risk?

We're being honest about this — it's the biggest live risk we manage:

- **ZENT classification:** intended to be a utility + governance token; we
  are engaging external counsel (Lex Crypta, with US fallback to Cooley)
  for formal opinions under US (Howey), EU (MiCA), and Singapore (SFA) law
- **Geographic strategy:** plan to block US users at the application layer
  at launch, MiCA-compliant in EU, Singapore-friendly. This is cheaper and
  faster than full US registration; we revisit post-launch
- **Entity:** target jurisdiction is BVI or Cayman for the operating
  entity, decided in tandem with counsel
- **Non-custodial design = limited regulatory surface.** Because no user
  funds touch a ZENTORY account, money-transmitter status is harder to
  attach. Securities classification is the live question

Mainnet launch is gated on completion of the legal opinion. We will not
launch with unresolved jurisdictional uncertainty.

## How big is the team?

Two co-founders today (Edge + Shaman). Edge runs algo + strategy + protocol
engineering. Shaman runs operations, public-facing communications, partner
+ legal workstreams. We expect to hire 1–2 more engineers post-audit using
treasury allocation.

We deliberately ran lean through testnet to validate the technical
hypothesis before scaling headcount. Now that the protocol is shipping and
audit-bound, controlled hiring resumes.

## What's the burn rate?

Detail under NDA. High-level: we operate at a level that lets the protocol
ship through Q3–Q4 2026 mainnet without additional capital, assuming the
audit + legal package land within budget. We are talking to selective
strategic capital but are not in a forced raise.

## What capital are you raising?

Selective strategic round, not a public fundraise. We prioritize:

- Strategic capital with HyperEVM ecosystem reach
- Advisors who can shorten the audit firm + legal counsel intake
- Tier-1 LP intros for the post-mainnet deposit ramp
- Crypto-native VCs with public track records (we vet investors as
  carefully as they vet us)

Term sheet structure under NDA. No CMS-public raise, no general public
solicitation.

## What's the launch sequence?

Public sequence, no surprises:

1. **Audit booked** (Q2 2026) — Spearbit/Cantina engagement
2. **Multisig migration on testnet** (parallel) — 3-of-5 Gnosis Safe
3. **Audit completion + remediation** (Q3 2026)
4. **Mainnet contract deploy** — same bytecode as testnet, Safe as admin
   from block 0
5. **TGE** — ZENT goes live on HyperSwap (primary) + Uniswap v3 bridged
   (secondary). 5–8% TGE float, rest vesting per published schedule
6. **Testnet user airdrop** — Merkle distributor, snapshot taken pre-launch
7. **KOL + PR campaign** — T-2 weeks pre-launch, target Tier-2/3 crypto
   press + crypto-native KOLs
8. **Bug bounty live** — Immunefi, same day as mainnet

Detailed mapping in [`docs/MULTISIG_MIGRATION_PLAN.md`](MULTISIG_MIGRATION_PLAN.md)
and `docs/AUDIT_OUTREACH.md`.

## What's the worst case for an investor?

Three failure modes we'd be honest about:

1. **Audit finds a critical vulnerability that requires significant
   refactor.** Adds 4–8 weeks to the timeline and possibly $50–100k of
   extra audit cost for re-review. Mitigation: internal pentest + Slither
   already triaged; we have a remediation budget reserved.
2. **Hyperliquid has a major outage or governance incident.** Our protocol
   degrades but doesn't lose principal — vault collateral sits in the EVM
   contract, not on Hyperliquid. Mitigation: mandate-bounded execution +
   permissionless circuit breaker.
3. **ZENT token gets classified as a security in a major jurisdiction.**
   Most painful scenario. Mitigation: launch with US blocked, structure
   for utility classification, engage counsel early. If it happens post-
   launch, we follow the playbook DeFi protocols pre-ZENTORY have run
   (geographic restrictions, registration path, or governance handover).

Every protocol has these risks. We're explicit about ours and how we
manage them.

## What do you want from this conversation?

If you're a strategic investor:
- Intros to HyperEVM ecosystem partners
- Audit firm and legal counsel referrals if you have specific
  relationships
- Tier-1 LP intros for post-launch
- Eyes on the protocol before mainnet — your feedback is more valuable
  pre-launch than post

If you're a financial-only investor:
- Honest read on whether the size + timeline fit your fund's profile
- Pass-through to better-matched investors if not — we'd rather know now

If you're an advisor:
- Specific 1–3 things you'd do differently in the launch sequence
- Connections in your network who'd benefit from this product

---

*Public version. Confidential financials, cap table, and term-sheet
specifics available under NDA via edge@zentorylabs.com.*
