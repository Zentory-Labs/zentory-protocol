# ZENTORY Protocol

**The Signal Arena on HyperEVM — non-custodial Alpha Vaults plus a verifiable on-chain quant reputation layer.**

ZENTORY is a protocol-grade DeFi stack that combines:

1. **Alpha Vaults** — ERC-4626 vaults over foundational crypto assets (BTC, ETH, SOL, XRP, HYPE) that earn yield in the **underlying asset**, not in an inflationary governance token.
2. **The Signal Arena** — an on-chain registry where quant researchers stake **ZENT** to post **EIP-712 signed** trading signals against those vaults, and where every signal's accuracy is settled in 4-hour epochs by a transparent scoring contract.
3. **Ghost Portfolio attribution** — for every vault, the protocol simultaneously tracks **HOLD** (passive baseline), **GHOST** (the path you would have taken following the signals), and **ACTUAL** (real on-chain NAV). Anyone can verify the alpha each signal contributed.

ZENTORY is **not** a token launchpad, an "investment discovery" directory, or a custodial copy-trading platform. The protocol is non-custodial by construction: depositors keep withdrawal rights at all times, and signal execution is bounded by a smart-contract mandate (`StrategyExecutor` + `HyperCoreAdapter`) that the quant signer cannot override.

| Resource | Location |
|----------|----------|
| Marketing site | [zentorylabs.com](https://zentorylabs.com) |
| dApp | [app.zentorylabs.com](https://app.zentorylabs.com) |
| Whitepaper v2 (May 2026) | [`docs/whitepaper.md`](docs/whitepaper.md) |
| Investor one-pager | [`docs/INVESTOR_ONE_PAGER.md`](docs/INVESTOR_ONE_PAGER.md) |
| Smart contracts | [`contracts/src/`](contracts/src) |
| Security policy | [`SECURITY.md`](SECURITY.md) |
| Strategy doc | [`STRATEGY.md`](STRATEGY.md) |
| Competitive map | [`COMPETITORS.md`](COMPETITORS.md) |
| Team | [`TEAM.md`](TEAM.md) |
| Contributing | [`CONTRIBUTING.md`](CONTRIBUTING.md) |
| X (Twitter) | [@ZENTORYLabs](https://twitter.com/ZENTORYLabs) |

---

## Problem Novelty

The crypto market today has **four structural defects** at the intersection of yield, signals, and reputation. ZENTORY is the first protocol designed to address all four together on a single L1.

### 1. Unverifiable "alpha"

Paid signal groups, Telegram VIP channels, and influencer trade calls form a market we estimate at **~$2.4B/year** in subscriptions, almost entirely off-chain (figure aggregated from public subscription sizes of leading signal providers and crypto-Twitter "premium tier" pricing surveys; see [`docs/INVESTOR_ONE_PAGER.md`](docs/INVESTOR_ONE_PAGER.md) for methodology). Track records are screenshots; "deleted bad trades" are the industry's open secret. There is no canonical, time-stamped, signer-bound log that a third party can audit. The current state of the art is "trust the screenshot."

### 2. Opaque vault yield

DeFi vaults publish an APY number without an honest comparison to *holding the asset*. A 7% APR vault on ETH that underperforms ETH-spot by 4% is destroying value, but the UI never tells you that. There is no industry-standard **attribution primitive** that separates passive beta, strategy alpha, and execution slippage.

### 3. Custodial copy-trading is the only mainstream option

eToro, Bitget Copy, Bybit Copy, and BingX Copy custody **your** assets to execute **their** mirror trades. Counterparty risk, withdrawal freezes, and opaque fill quality come bundled. There is no copy-trading product that lives entirely in your wallet and a smart contract — the closest analogues (dHEDGE, Enzyme) require trusting a fund manager and don't include a verifiable signal feed.

### 4. No native quant reputation layer on HyperEVM

HyperEVM crossed **$2.8B TVL** with **175+ teams** building on it in 2025-2026 (source: DefiLlama HyperEVM chain page and Hyperliquid ecosystem map; figures verified May 2026), and **Hyperliquid** is one of the deepest on-chain perp venues by volume. Yet there is no protocol-level identity for *quants* on HyperEVM — no `ve` token tied to signal accuracy, no slashable stake bond, no Sybil-resistant scoring. The ecosystem has the liquidity and the execution layer; it is missing the **signal market** that makes the liquidity productive for non-experts.

**The novelty:** ZENTORY is the first protocol to bind these four problems into a single, vertically-integrated stack:

```
HyperEVM (settlement)
   │
   ├── ERC-4626 Alpha Vaults  ← user assets, non-custodial
   │       │
   │       ▼
   ├── StrategyExecutor (mandate-bounded)
   │       │
   │       ▼
   ├── HyperCoreAdapter ──► Hyperliquid (execution)
   │       │
   │       ▼
   ├── SignalRegistry (EIP-712, ZENT-staked)
   │       │
   │       ▼
   └── EpochScoring + Ghost Portfolio ──► public attribution
```

Each layer maps directly to one of the four problems above; remove any one and the moat breaks.

---

## Ecosystem Position

### Market context

| Adjacent market | Approx. size (2025/26) | Why ZENTORY plays here |
|---|---|---|
| HyperEVM DeFi TVL | ~$2.8B and growing | Native L1; vaults sit at the base |
| Crypto quant signals (paid, off-chain) | ~$2.4B in subs/yr | Direct replacement target |
| DeFi-native copy-trading | ~$5B notional | Non-custodial alternative |
| Vault aggregators (Yearn/Beefy generation) | $10B+ historical peak | Reframes "vault" as a quant venue |
| Reputation/competition protocols (Numerai, Polymarket) | $1B+ combined market caps | Layer borrowed from these, applied to vaults |

HyperEVM in 2026 occupies the position Ethereum DeFi held in 2020: high liquidity, fast-growing developer count, no entrenched "BlackRock of HyperEVM" yet. Yearn was founded into that window for Ethereum; ZENTORY is being built into the equivalent window for HyperEVM.

### Why this is not saturated

A common critique is "vaults are commoditized." That is true for **simple** vaults (auto-compound a lending position). It is **not** true for the surface ZENTORY targets:

- **No** existing HyperEVM vault publishes a Ghost / Hold / Actual attribution triple on-chain.
- **No** existing copy-trading product is non-custodial *and* HyperEVM-native *and* signal-feed transparent.
- **No** existing quant-reputation protocol (Numerai, Polymarket Pros) is wired into a real ERC-4626 vault that an end user can deposit into in one click.
- Numerai is hedge-fund opaque; Polymarket is event-prediction, not vault execution; Yearn / Beefy have no signer identity; eToro is custodial; dHEDGE is fund-manager based, not signal-based.

The white space ZENTORY targets is the intersection of all five, which is currently empty.

### Why now

1. **HyperEVM liquidity unlock.** Hyperliquid perps + HyperEVM smart contracts give the protocol a real venue that didn't exist in 2022.
2. **Account abstraction + EIP-712 ubiquity.** Cheap, gas-efficient signature schemes make per-signal cryptographic attribution practical.
3. **AI-augmented quant supply.** The pool of independent researchers who can credibly run systematic strategies has 10x'd post-2023.
4. **Custody fatigue.** Post-FTX, custodial copy-trading has a permanent compliance and PR overhang.

---

## Solution Differentiation

The mechanism that makes ZENTORY structurally different is the **Ghost Portfolio** plus the **mandate-bounded StrategyExecutor**.

### Ghost Portfolio (the attribution primitive)

For every vault, three balances are tracked in parallel:

| Track | Definition | Answers the question |
|---|---|---|
| **HOLD** | What the vault would be worth if it just held the underlying asset since inception | "Am I beating the market?" |
| **GHOST** | What the vault would be worth if every accepted signal were executed at the price stamped in the signal | "Are the *signals* good?" |
| **ACTUAL** | What the vault is *actually* worth right now, including real slippage and fees | "How much execution leakage am I paying?" |

The gap **ACTUAL − HOLD** is total alpha. The gap **GHOST − HOLD** is signal alpha. The gap **ACTUAL − GHOST** is execution alpha (positive or negative). Every number is reconstructible from on-chain events — no trust required.

This is the **first** attribution primitive of its kind delivered as on-chain primitives + an indexer ([`engine/scripts/index_strategy_executor_events.py`](engine/scripts/index_strategy_executor_events.py), [`engine/scripts/poll_hyperliquid_fills.py`](engine/scripts/poll_hyperliquid_fills.py)) rather than a marketing dashboard.

### Mandate-bounded execution

[`contracts/src/keeper/StrategyExecutor.sol`](contracts/src/keeper/StrategyExecutor.sol) enforces in Solidity:

- `maxPositionSize` per vault
- `maxLeverageBPS` per vault (batchable)
- per-vault `nonce` and `expiry` on every signal
- EIP-712 signature from an `authorizedSigner` the vault governs
- `GUARDIAN_ROLE` circuit breaker (`setPaused`)

A signer cannot exceed mandate, replay, or sign a stale signal. This makes "copy-trading without custody" mechanically possible.

### Named-competitor diff

| Capability | ZENTORY | Numerai | Yearn / Beefy | eToro / Bitget Copy | dHEDGE / Enzyme | Polymarket | Paid Telegram signals |
|---|---|---|---|---|---|---|---|
| Non-custodial (user keeps keys) | Yes | n/a | Yes | No | Yes | Yes | Yes (but no execution) |
| On-chain signal registry (EIP-712) | Yes | No (centralized) | No | No | No (fund mgr discretion) | No | No |
| Per-signal accuracy settled on-chain | Yes | Internal only | No | No | No | Outcome only | No |
| Vault attribution (Hold / Ghost / Actual) | Yes | No | No | No | No | No | No |
| Reputation token w/ slash + stake | Yes (ZENT) | Yes (NMR) | No | No | No (mgr fee only) | Partial | No |
| HyperEVM native | Yes | No | No | No | No | No | No |
| Hyperliquid execution adapter | Yes | No | No | n/a (their CEX) | Limited | No | No |
| Buyback + burn from real revenue | Yes | No | No | No | No | No | No |
| Fixed-supply utility token (no inflation) | Yes | No | n/a | n/a | n/a | n/a | n/a |

The cell-by-cell pattern is the differentiation: **every competitor checks one or two of these boxes; only ZENTORY targets the full matrix.**

### What ZENTORY is *not*

- Not a security or share of vault revenue. ZENT is utility + governance; vault depositors earn the **underlying** asset.
- Not a token-launchpad / IDO platform.
- Not a directory of third-party crypto/AI projects.
- Not a discretionary fund — every action is mandate-bounded smart-contract code.
- Not a custodian — withdrawals are EIP-4626 share redemptions on demand.

---

## Quick verification surfaces

These are the auditable artifacts in this repository. Anyone evaluating the project (investors, security researchers, rating platforms, journalists) can verify the substance of the claims above directly.

### Smart contracts (Solidity 0.8.28, Foundry)

26 contracts in [`contracts/src/`](contracts/src), grouped by subsystem:

| Subsystem | Key contracts |
|---|---|
| Token | [`ZENT.sol`](contracts/src/ZENT.sol), [`ZENTVesting.sol`](contracts/src/ZENTVesting.sol), [`ZENTBuyback.sol`](contracts/src/ZENTBuyback.sol), [`ProtocolTreasury.sol`](contracts/src/ProtocolTreasury.sol) |
| Vaults (ERC-4626) | [`vaults/BaseVault.sol`](contracts/src/vaults/BaseVault.sol), `zBTCVault.sol`, `zETHVault.sol`, `zSOLVault.sol`, `zXRPVault.sol` |
| Staking & bonding | [`staking/ZENTStaking.sol`](contracts/src/staking/ZENTStaking.sol), [`staking/ModelBonding.sol`](contracts/src/staking/ModelBonding.sol) |
| Fees | [`fees/FeeDistributor.sol`](contracts/src/fees/FeeDistributor.sol) |
| Execution | [`keeper/StrategyExecutor.sol`](contracts/src/keeper/StrategyExecutor.sol), [`keeper/HyperCoreAdapter.sol`](contracts/src/keeper/HyperCoreAdapter.sol) |
| Signals | [`signals/SignalRegistry.sol`](contracts/src/signals/SignalRegistry.sol), [`signals/EpochScoring.sol`](contracts/src/signals/EpochScoring.sol), [`signals/SubscriptionVault.sol`](contracts/src/signals/SubscriptionVault.sol) |
| Governance | [`governance/Timelock.sol`](contracts/src/governance/Timelock.sol), [`governance/ZentGovernor.sol`](contracts/src/governance/ZentGovernor.sol), [`governance/Zentroller.sol`](contracts/src/governance/Zentroller.sol) |

### Tests, fuzzing, invariants

18 test files in [`contracts/test/`](contracts/test), including dedicated fuzz suites ([`fuzz/BaseVault.fuzz.t.sol`](contracts/test/fuzz/BaseVault.fuzz.t.sol), [`fuzz/StrategyExecutor.fuzz.t.sol`](contracts/test/fuzz/StrategyExecutor.fuzz.t.sol)), invariant suites ([`invariants/BaseVault.inv.t.sol`](contracts/test/invariants/BaseVault.inv.t.sol), [`invariants/StrategyExecutor.inv.t.sol`](contracts/test/invariants/StrategyExecutor.inv.t.sol)), and a Python↔Solidity EIP-712 digest parity test ([`crosslanguage/DigestParity.t.sol`](contracts/test/crosslanguage/DigestParity.t.sol)).

### Off-chain stack

- **dApp** ([`frontend/`](frontend)) — Next.js 16 + React 19 + wagmi + viem + Supabase + Upstash; routes for vaults, staking, signals, governance, leaderboard, subscriptions, contributor flow.
- **Engine** ([`engine/`](engine)) — Python 3.11+ package `zentory-engine` with EIP-712 signer ([`src/signals/signer.py`](engine/src/signals/signer.py)), Hyperliquid execution client, GP/strategy research lab, on-chain event monitor, log indexers.
- **Keeper bot** ([`contracts/keeper/`](contracts/keeper)) — TypeScript epoch-settlement keeper (viem + Supabase + CoinGecko) that drives `EpochScoring`.

### CI

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs Foundry build + test (with the cross-language FFI signer step), Slither static analysis, Python engine pytest, and frontend build + Playwright + Vercel preview deploy on every PR.

### Security

- Disclosure policy: [`SECURITY.md`](SECURITY.md) (Immunefi when live, otherwise `security@zentorylabs.com`, with stated SLAs).
- Internal audit notes: [`contracts/scripts/audit/`](contracts/scripts/audit).
- Pentest record: [`docs/reports/pentest-2026-04-26.md`](docs/reports/pentest-2026-04-26.md).
- Verification master plan (G1–G10 gates): [`docs/plans/2026-04-25-001-verification-master-plan.md`](docs/plans/2026-04-25-001-verification-master-plan.md).

---

## Token model (ZENT)

ZENT is a **fixed-supply utility and governance** token. Fixed at **1,000,000,000** ZENT, **no inflation, no emissions**.

### What ZENT is

- **Signal-staking collateral.** Quants stake ZENT against each signal they submit; high accuracy mints reputation, low accuracy is slashed up to a per-epoch cap (whitepaper §7.2; see also §6.1 for the full utility table).
- **Conviction weight.** 1 ZENT staked = 1 conviction point on a signal; conviction routes auto-follow execution.
- **Access tiers.** Premium vault tiers and signal subscriptions require minimum stake.
- **Governance.** `veZENT`-style voting (lock 7–730 days) over protocol parameters, new vaults, treasury grants, upgrades (66% supermajority for upgrades).
- **Fee payment.** Subscription tiers can be paid in ZENT (`SubscriptionVault`).

### What ZENT is **not**

- Not a share of vault revenue.
- Not a yield-bearing instrument intrinsic to holding the token.
- Not an equity claim.
- Not a security under Howey when used as described (see [`docs/BUYBACK_DESIGN.md`](docs/BUYBACK_DESIGN.md) for the buyback memo).

### Fee → token loop

Vault performance fees (per whitepaper v2 §6: **15%** on yield) route through [`FeeDistributor.sol`](contracts/src/fees/FeeDistributor.sol). The current split in §6.4 of the whitepaper allocates:

- 50% → **buyback and burn** ZENT
- 25% → treasury (quant grants, audits)
- 15% → insurance fund
- 10% → operations

The buyback connects real protocol revenue to a deflationary force on the fixed supply. There is no inflationary subsidy in this design.

---

## Architecture at a glance

```
┌──────────────────┐        ┌──────────────────┐
│  Quant signer    │        │   Vault user     │
│  (off-chain)     │        │  (any wallet)    │
└────────┬─────────┘        └────────┬─────────┘
         │ EIP-712                   │ deposit BTC/ETH/SOL/XRP/HYPE
         ▼                           ▼
┌─────────────────────────────────────────────────┐
│              HyperEVM (chain id 998)            │
│                                                 │
│  SignalRegistry ──► EpochScoring ──► ZENT (slash/reward)
│        ▲                                        │
│        │                                        │
│  StrategyExecutor ──► HyperCoreAdapter          │
│        ▲                    │                   │
│        │                    ▼                   │
│  BaseVault (ERC-4626) ◄── Hyperliquid (perps)   │
│        │                                        │
│        ▼                                        │
│  FeeDistributor ──► Buyback / Treasury / Insurance / Ops
└─────────────────────────────────────────────────┘
         ▲                           ▲
         │ Supabase index            │ engine indexer
         │ + dApp                    │ + monitor
         ▼                           ▼
   app.zentorylabs.com         engine/ (Python)
```

---

## Team

Maintained by ZENTORY Labs. Named contributors, verifiable handles, and contact in [`TEAM.md`](TEAM.md).

For business inquiries: `contact@zentorylabs.io`
For security: `security@zentorylabs.com`
For social: [@ZENTORYLabs](https://twitter.com/ZENTORYLabs)

---

## Status

- **Live now (HyperEVM testnet, chain id 998):** all 26 protocol contracts deployed; full Foundry deploy pipeline ([`contracts/script/DeployPipeline.s.sol`](contracts/script/DeployPipeline.s.sol)); Hyperliquid fill-indexing pipeline (whitepaper §12); dApp at app.zentorylabs.com; engine indexer + signal-network keeper.
- **In progress (May 2026):** Ghost Portfolio scoring UI, Conviction leaderboard, Auto-Follow, Volatility Brackets S1, production-grade monitoring + alerting.
- **Q4 2026 gate:** external audit + mainnet.
- **2027:** multi-chain, equity signals, governance launch.

---

## Open Source Policy

The ZENTORY protocol is built in two layers:

### Public layer — `zentory-protocol` (this repo, BSL 1.1)

The trust layer is fully public. Smart contracts, tests, deploy scripts, the epoch-settlement keeper, and all strategic documentation (this README, STRATEGY, COMPETITORS, whitepaper) live here under **Business Source License 1.1**.

BSL 1.1 means:
- Anyone can **read** the contracts, audit them, and build open-source integrations.
- Commercial forks (hosted services that compete with ZENTORY Protocol) are blocked from launching **until September 30, 2030** — 4+ years of runway to earn distribution before any copycat can legally compete.
- On September 30, 2030 the license automatically converts to **GPL-3.0** and the code is fully open forever.

This is the same license Uniswap V4 uses. It is the right balance: **open enough to be trusted, closed enough to protect the business**.

### Closed layer — `zentory-engine` (private forever)

The research engine that **generates** trading signals lives in a **private repository**. It is never published.

What the engine produces (EIP-712 signed signals, accuracy scores settled on-chain by `EpochScoring`) is **fully public** — anyone can verify on-chain that a signal was posted, that ZENT was staked, and what the 4-hour-epoch accuracy score was. What the engine uses to decide *which* signals to post is proprietary.

This is the same model Numerai uses (public scoring contract, private model weights), and the same model every serious trading firm in the world uses. Users verify **output quality** on-chain; ZENTORY Labs keeps the **methodology** private.

### Why not fully open source?

Fully open-sourcing the engine would mean publishing the strategy parameters, genetic programming configurations, and the complete signal-generation methodology. That is the alpha. Publishing it would let any HyperEVM deployment clone the signal-generation layer immediately, at zero cost, with no R&D required.

We chose BSL 1.1 for the protocol contracts because they will be on the block explorer at mainnet anyway (verified contracts are how DeFi users assess safety — unverified = unsafe). Making them readable 6 months early builds verifiable track record. The BSL prevents a competitor from packaging them into a hosted competing service before September 2030.

For questions about commercial licensing of the protocol contracts, contact: `contact@zentorylabs.io`

---

## Repository layout

After the ZENTORY Labs organization split (completed May 2026), this repository (`Zentory-Labs/zentory-protocol`) contains:

```
zentory-protocol/
├── contracts/          Solidity 0.8.28 + Foundry
│   ├── src/           26 contracts, grouped by subsystem
│   ├── test/          18 test files (unit + fuzz + invariants + xlang)
│   ├── script/        Forge deploy + simulate scripts
│   └── keeper/        TypeScript epoch-settlement keeper
├── supabase/          Migrations + edge functions
├── docs/              Whitepaper, plans, runbooks, reports
├── packages/zentory-ui Shared design tokens + Tailwind preset
└── scripts/           Ops helpers
```

The three related repos are:

| Repo | License | Contents |
|---|---|---|
| [`Zentory-Labs/zentory-app`](https://github.com/Zentory-Labs/zentory-app) | AGPL-3.0 | dApp source (Next.js 16 + wagmi + viem) → app.zentorylabs.com |
| [`Zentory-Labs/zentorylabs.com`](https://github.com/Zentory-Labs/zentorylabs.com) | MIT | Marketing site → zentorylabs.com |
| [`Zentory-Labs/zentory-engine`](https://github.com/Zentory-Labs/zentory-engine) | Proprietary | Strategy research engine (GP, signer, indexer, executor) — **private forever** |

For build, deploy, and ops procedures see [`DEPLOYMENT.md`](DEPLOYMENT.md). For security disclosure see [`SECURITY.md`](SECURITY.md). For the high-level commercial framing see [`STRATEGY.md`](STRATEGY.md) and [`docs/INVESTOR_ONE_PAGER.md`](docs/INVESTOR_ONE_PAGER.md).

---

## Legal

Nothing in this repository is financial, legal, tax, or investment advice. ZENT is a utility and governance token; participation in vaults or signal staking is offered subject to jurisdictional eligibility, KYC where applicable, and the limitations documented in [`docs/regulatory-memo.md`](docs/regulatory-memo.md) and [`docs/GEOBLOCKING.md`](docs/GEOBLOCKING.md). Smart contracts are provided **as-is** under active development and pending external audit (Q4 2026, per current roadmap). Use at your own risk; on testnet today.

---

*ZENTORY Labs — building the verifiable signal market for HyperEVM.*
