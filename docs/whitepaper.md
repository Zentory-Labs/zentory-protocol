# ZENTORY Protocol — Technical Whitepaper

**Version 2.0 — May 2026**

**Authors:** ZENTORY Labs Core Development Team

**Status:** Testnet Deployed on HyperEVM (Chain ID: 998)

---

> **Important Notice:** This document is for informational purposes only. ZENTORY is under active development. All contract parameters, fee schedules, and technical specifications are subject to change via on-chain governance. Nothing in this document constitutes financial, legal, or investment advice. Past performance of any signal provider is not indicative of future results. Cryptocurrency trading involves substantial risk of loss. ZENT is a utility token governing protocol operations — it does not represent ownership, revenue share, or any security interest in the protocol or its affiliates.

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [The Problem](#2-the-problem)
3. [The Solution: The Signal Arena](#3-the-solution-the-signal-arena)
4. [Core Product Features](#4-core-product-features)
5. [Protocol Architecture](#5-protocol-architecture)
6. [Token Economics](#6-token-economics)
7. [Signal Flow](#7-signal-flow)
8. [Ghost Portfolio & Attribution](#8-ghost-portfolio--attribution)
9. [Legal Framework](#9-legal-framework)
10. [Smart Contract Security](#10-smart-contract-security)
11. [Governance](#11-governance)
12. [Roadmap](#12-roadmap)
13. [Team & Legal](#13-team--legal)

---

## 1. Executive Summary

### 1.1 What ZENTORY Is

ZENTORY is a **decentralized quant signal exchange and vault ecosystem** built on HyperEVM. It has two interconnected layers:

1. **Alpha Vaults** — Non-custodial, ERC-4626 vaults (zBTC, zETH, zSOL, zXRP) that generate yield through a proprietary trading system. Depositors earn real asset yield by holding in the vault, not by speculating on ZENT.

2. **The Signal Arena** — A social layer where quants stake ZENT to submit signals, ranked by a Conviction Score that reveals how much skin-in-the-game each quant has. Followers auto-copy top quants. The Ghost Portfolio shows what following signals would have returned vs. holding vs. the actual vault.

ZENT is the **utility token** governing both layers. It is not a security, does not entitle holders to vault revenue, and is not marketed as an investment vehicle.

### 1.2 The Reference Stack

| Layer | Reference | ZENTORY Adaptation |
|---|---|---|
| Vault architecture | Yearn Finance, Beefy Finance | ERC-4626, non-custodial, multi-asset |
| Quant reputation | Numerai | On-chain signal history, ZENT-staked conviction |
| Social proof | ORBT Protocol | Shareable ZENTORY Score cards |
| Copy trading | uwuu, Replicate | Auto-follow on Hyperliquid, non-custodial |
| Engagement loop | Hype Finance, AntNest | Daily ritual, volatility brackets |
| Legal safety | — | Utility token only; no profit distribution |

### 1.3 The One-Line Differentiator

> **ZENTORY is the only place on HyperEVM where you can deposit BTC and earn yield, follow the quants who actually believe in their own research, and prove — on-chain — whether following signals beat holding.**

### 1.4 Key Numbers

| Metric | Value |
|---|---|
| ZENT Token Supply | 1,000,000,000 (fixed, 18 decimals) |
| Blockchain | HyperEVM (Chain ID: 998 — testnet) |
| Vault Assets | zBTC, zETH, zSOL, zXRP |
| Vault Performance Fee | 15% of yield generated |
| Signal Epoch | 4 hours |
| Quant Slash (max) | 1.7% of staked ZENT per epoch |
| Quant Reward (max) | 5.0% of staked ZENT per epoch |
| Min ZENT to Submit Signals | 100 ZENT |
| Min Lock Duration | 7 days |
| Max Lock Duration | 730 days (veZENT model) |
| ZENTORY Score Tiers | Bronze / Silver / Gold / Diamond |
| Conviction Score | ZENT staked per signal (1 ZENT = 1 point) |

---

## 2. The Problem

### 2.1 Retail Loses Because the Best Signal is Behind a Paywall

The crypto quant market is worth an estimated $2.4B annually. Most signal channels operate in private Discords and Telegram groups. Subscribers pay subscription fees for signals they cannot evaluate historically — they are buying blind. The people with the best track records charge the most and reveal the least.

Meanwhile, the people who could benefit most — everyday BTC/ETH holders — have no credible, affordable way to access quant research.

### 2.2 Copy Trading Platforms Are Either Centralized or Useless

The major copy trading platforms (eToro, NAGA, Bitget) are centralized. You deposit money into their platform, they execute trades on your behalf. You have counterparty risk. They can freeze your account. They show "past performance" which is usually front-loaded.

On DeFi, copy trading is nearly nonexistent on HyperEVM despite $2.8B in ecosystem TVL. What little exists requires trusting a smart contract you cannot audit, with no track record transparency.

### 2.3 No Reputation Exists On-Chain for Quants

In TradFi, a fund manager's 10-year Sharpe ratio is their reputation. In DeFi, a quant's "track record" is a screenshot of a Telegram message. Nothing is permanently verifiable. Nothing is on-chain. A quant can build a following on fake results and exit with no trace.

### 2.4 Vault Yield Is Boring and Invisible

Yearn and Beefy generate real yield. But the UX is: "here is your estimated APY." There is no social engagement. No one tweets: "I'm up 4.2% this month from Yearn." There is nothing to show friends. The product has no virality.

### 2.5 Regulatory Risk for Most Protocols

Most DeFi protocols that pay out yield in their native token are making securities promises. "Stake our token and earn yields" is the exact structure regulators flag. The ones that survive are those that separate token utility from profit distribution cleanly.

---

## 3. The Solution: The Signal Arena

The Signal Arena is a social exchange for quant research built on top of the Alpha Vaults. It is not a prediction market. It is not a managed fund. It is a permissionless reputation layer where quants bet ZENT on their own research, and followers decide whether to act.

The five core features that make it work:

1. **Conviction Scores** — Quant signals are weighted by ZENT staked on them
2. **ZENTORY Score** — Shareable reputation card for every wallet
3. **Ghost Portfolio** — On-chain proof of what following signals would have returned
4. **Auto-Follow** — Non-custodial copy trading on Hyperliquid
5. **Volatility Brackets** — 48-hour competitive tournaments during market stress

Each feature is described in full in Section 4.

---

## 4. Core Product Features

### 4.1 Conviction Scores

Every signal a quant submits carries a **Conviction Score**: the amount of ZENT the quant stakes on that signal. This is the primary ranking mechanism on the ZENTORY leaderboard.

**How it works:**

- A quant submits a signal: "LONG BTC-PERP"
- They stake 10,000 ZENT on this signal → Conviction Score: **10,000**
- A different quant submits the same signal, stakes 100 ZENT → Conviction Score: **100**
- The leaderboard ranks by a **conviction-weighted accuracy score**: accuracy × log(1 + conviction_staked)

**Why this is different:**

- A 99% accurate quant with 100 ZENT staked shows up lower than a 75% accurate quant who staked 50,000 ZENT
- This reveals who actually believes in their research
- Amateur signal spammers wash out because they won't stake real ZENT
- Professional quants can prove conviction by staking significant amounts

**Economic design:**

- Staked ZENT is locked for the duration of the signal (minimum 4 hours, maximum 30 days)
- If the signal resolves correctly, the staked ZENT is returned + a reward from the protocol treasury
- If the signal resolves incorrectly, the staked ZENT is partially slashed (Numerai-style)
- The slash/reward formula: `payout_factor = (accuracyBps / 10000) × 2 − 1`, scaled by 0.3, clipped to [-1.7%, +5.0%]

**Legal safety:**

- Rewards come from the **protocol treasury** (funded by vault fees), not from vault depositor funds
- Quants are not running a fund — they are submitting informational research and staking ZENT for reputation
- There is no guarantee of reward; staking is at risk

### 4.2 ZENTORY Score

The ZENTORY Score is a **shareable reputation card** generated for any connected wallet. It is the primary viral loop of the protocol.

**Components of the score (0–1000):**

| Component | Weight | What it measures |
|---|---|---|
| Vault Loyalty | 25% | Age of deposits, consistency of holdings |
| Quant Performance | 25% | Signal accuracy weighted by conviction |
| ZENT Stake Age | 20% | How long ZENT has been locked (veZENT) |
| Network Participation | 15% | Followers, referrals, following |
| Social Engagement | 15% | Score cards shared, comments, tips given |

**Score tiers:**

| Tier | Score Range | Badge Color |
|---|---|---|
| Bronze | 0–249 | Bronze |
| Silver | 250–499 | Silver |
| Gold | 500–749 | Gold |
| Diamond | 750–1000 | Diamond (animated) |

**Viral mechanism (proven by ORBT Protocol):**

- Users connect wallet → generate shareable ZENTORY Score card
- Card is an image + link showing score, tier, and rank
- Share to Twitter/X → drives referral traffic
- Referral codes embedded in cards earn additional ZENT Score points
- ORBT generated 70,000 shared cards and 20M impressions with a simpler version

**Legal safety:**

- The score is purely reputation — it does not promise returns
- Score cards carry disclaimer: "This is not financial advice. Past performance is not indicative of future results."
- Score does not entitle holder to any revenue or fee discount (separate tier system governs access)

### 4.3 Ghost Portfolio

The Ghost Portfolio is ZENTORY's most technically unique feature. It is the **on-chain verifiable proof** of what following quant signals would have returned.

**How it works:**

1. Every signal is recorded on-chain in `SignalRegistry` with a timestamp
2. The indexer tracks every fill from Hyperliquid into `hl_user_fills`
3. For each vault, the system computes three simultaneous portfolios:

```
Portfolio A (HOLD):       What you earn by just holding the asset (BTC baseline)
Portfolio B (GHOST):      What you earn if you followed every quant signal at face value
Portfolio C (ACTUAL):     What the vault actually generated through its trading system
```

4. The gaps between these portfolios are the core ZENTORY metrics:
   - **Ghost vs. HOLD** = signal value (did following quants beat holding BTC?)
   - **Actual vs. Ghost** = execution alpha (did the trading system beat the signals?)
   - **Actual vs. HOLD** = total vault value (did the vault beat BTC?)

**Why it is verifiable:**

- Signals are on-chain: `SignalRegistry` with EIP-712 signatures, timestamps, asset, direction, confidence
- Fills are on-chain: Hyperliquid `userFills` indexed via `hl_user_fills`
- Attribution is algorithmic: a fill within a time window after a signal is attributed to that signal
- Any user can verify the Ghost Portfolio computation against their own wallet history

**This is impossible to fake.** A protocol can claim alpha all day — the Ghost Portfolio shows it.

**The marketing hook:**

- "My Ghost is up 34% this year and I never made a trade"
- Screenshots of the three-line chart (GHOST vs. HOLD vs. ACTUAL) become the organic content loop
- It is the single most powerful proof point ZENTORY has

**Ghost Portfolio display (dashboard):**

```
═══════════════════════════════════════════════════════
  zBTC Vault — Last 90 Days
────────────────────────────────────────────────────
  HOLD (BTC baseline)        +2.3%
  GHOST (follow signals)    +18.7%  ← tweet this
  ACTUAL (vault performance)+23.1%  ← trading system alpha
────────────────────────────────────────────────────
  Signal Value:    +16.4% vs HOLD
  Execution Alpha:  +4.4% vs GHOST
  Total Alpha:     +20.8% vs HOLD
═══════════════════════════════════════════════════════
```

### 4.4 Auto-Follow (Copy Trading)

Auto-Follow allows any vault depositor to automatically mirror the trades of a top-ranked quant without surrendering custody of their funds.

**How it works:**

1. User browses the ZENTORY quant leaderboard (ranked by conviction-weighted accuracy)
2. User clicks "Auto-Follow" on a quant
3. User's wallet is linked to the signal feed for that quant (via an on-chain signal routing contract)
4. When the quant submits a signal, the routing contract executes an equivalent position in the user's vault balance
5. User can stop following at any time — no lock-up, no penalty

**Why it is non-custodial:**

- User funds never leave the vault
- The signal routing contract has **limited mandate**: it can only execute within the user's existing vault balance
- It cannot withdraw, transfer, or deploy user funds outside the vault
- The user's private keys are never held by ZENTORY or any associated entity

**vs. centralized copy trading:**

| Feature | Centralized (eToro/Bitget) | ZENTORY Auto-Follow |
|---|---|---|
| Custody | Platform holds funds | User holds keys |
| Transparency | Proprietary | Full on-chain |
| Track record | Self-reported | EIP-712 verified |
| Counterparty risk | Yes | None |
| Cancel anytime | May have lock-up | Instant |

**vs. other DeFi copy trading:**

| Feature | Other DeFi copy trading | ZENTORY Auto-Follow |
|---|---|---|
| Chain | Ethereum/Solana | HyperEVM (native) |
| Signal attribution | Often off-chain | On-chain fills |
| Conviction signal | None | ZENT-staked conviction |
| Vault integration | None | Native to vault |

### 4.5 Volatility Brackets

Volatility Brackets are **48-hour competitive tournaments** that activate when BTC moves more than 3% in a single hour. They are the appointment-TV moment that drives daily engagement.

**Trigger conditions:**

- BTC price moves ≥3% within 1 hour (measured by Chainlink price feed)
- A 48-hour bracket opens automatically
- Top 8 ranked quants are invited to compete

**Tournament mechanics:**

- Each quant receives a paper $1,000 virtual vault (no real funds)
- They submit real signals during the bracket
- Signals are tracked against live BTC price action
- Winner is the quant with the highest return on their paper vault at bracket close

**Rewards:**

- Winner: ZENT from protocol treasury + on-chain "Volatility Champion" badge (ERC-721)
- 2nd–3rd: Smaller ZENT allocation from treasury
- All participants: ZENTORY Score boost proportional to bracket rank
- Followers: Live bracket view with quant positions and leaderboard

**Why this drives engagement:**

- It creates **appointment content**: traders check the bracket during high-volatility events
- It is **verifiable**: all signals are on-chain, all results are computable
- It is **legally clean**: prizes come from protocol treasury (not vault funds), structured as a competition
- It generates **social content**: winner tweets, bracket screenshots, leaderboard drama

**The Hype comparison:**

Hype's success came from making DeFi feel like a sport. Volatility Brackets do the same for quant research: instead of watching one trader, you watch eight compete in real time during the most important market moments.

---

## 5. Protocol Architecture

### 5.1 System Overview

The ZENTORY Protocol consists of three layers:

**Layer 1 — Smart Contracts (HyperEVM)**

- Alpha Vaults (zBTC, zETH, zSOL, zXRP) — ERC-4626, non-custodial
- SignalRegistry — EIP-712 signed signal log
- EpochScoring — 4-hour settlement, Numerai-style payout
- ZENTStaking — veZENT, slash/reward
- FeeDistributor — vault fee routing, treasury
- Zentroller + ZentGovernor — governance

**Layer 2 — Indexer Engine (Off-chain)**

- Hyperliquid fill poller: `poll_hyperliquid_fills.py` → `hl_user_fills`
- On-chain event indexer: `index_strategy_executor_events.py` → `execution_attempts`
- Ghost Portfolio computation engine
- ZENTORY Score calculator

**Layer 3 — Frontend (User-facing)**

- Vault deposit/withdraw UI
- Signal Arena: leaderboard, conviction scores, auto-follow
- Ghost Portfolio charts (three-line: HOLD / GHOST / ACTUAL)
- ZENTORY Score card generator

### 5.2 Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                      USER LAYER                             │
│  Vault Depositor    Quant (Signal Provider)    Follower     │
└──────────────┬──────────────────┬──────────────────────────┘
               │                  │
               ▼                  ▼
┌──────────────────────────┐  ┌─────────────────────────────────┐
│      Alpha Vaults         │  │      SignalRegistry (on-chain)   │
│  zBTC / zETH / zSOL / zXRP│  │  EIP-712 signed signal log       │
│  ERC-4626, non-custodial  │  │  SignalSubmitted events          │
└──────────┬─────────────────┘  └──────────────┬────────────────┘
           │                                       │
           │  Vault yields                        │ Signals
           │  (execution_attempts)                │
           ▼                                       ▼
┌──────────────────────────────────────────────────────────────┐
│                    INDEXER ENGINE (off-chain)                 │
│                                                              │
│  poll_hyperliquid_fills.py  →  hl_user_fills (Supabase)     │
│  index_strategy_executor_events.py → execution_attempts       │
│                                                              │
│  Ghost Portfolio computation                                 │
│  ZENTORY Score calculation                                   │
│  Conviction Score aggregation                               │
└──────────────────────────────────────────────────────────────┘
           │
           ▼
┌──────────────────────────────────────────────────────────────┐
│                    FRONTEND (app.zentorylabs.com)             │
│                                                              │
│  /dashboard          /vaults         /signal-arena            │
│  Ghost charts       Deposit/Withdraw Leaderboard + Auto-Follow│
│  ZENTORY Score card                     Volatility Brackets   │
└──────────────────────────────────────────────────────────────┘
```

---

## 6. Token Economics

### 6.1 ZENT Token

**Specification:**

- **Token Name:** Zentory Token
- **Symbol:** ZENT
- **Standard:** ERC-20 with ERC20Votes and ERC20Permit
- **Total Supply:** 1,000,000,000 (1 billion) fixed, 18 decimals
- **No inflation. No admin mint on mainnet.**

**ZENT Utility (four distinct uses):**

| Use | Mechanism | Legal Status |
|---|---|---|
| **Signal staking** | Stake ZENT per signal; slashed on wrong, rewarded on correct | Utility — gates signal submission |
| **Vault access** | Stake ZENT to access vault deposits (minimum tier) | Utility — gates vault features |
| **Governance** | veZENT voting in ZentGovernor | Utility — governance participation |
| **Fee payment** | Pay vault fees and subscription tiers in ZENT (discount) | Utility — payment instrument |

**ZENT is NOT:**
- A share of vault revenue
- An entitlement to yield from vault deposits
- A security representing ownership in ZENTORY Labs
- A promise of profit from signal accuracy

### 6.2 Deflation Mechanism

50% of all vault performance fees are used to buy back ZENT from the market and burn it (send to 0xdead). This creates deflationary pressure proportional to protocol usage. The other 50% flows to the protocol treasury.

```
Vault generates $100 in performance fees:
  → $50 → ZENT buyback → burn (0xdead)
  → $50 → Protocol treasury → quant grants, operations, treasury
```

### 6.3 Supply Allocation (TBD — pre-mainnet disclosure)

| Category | Allocation | Lock Schedule |
|---|---|---|
| Public Sale | TBD | TBD |
| Team & Advisors | TBD | 4-year vest |
| Ecosystem / Grants | TBD | TBD |
| Protocol Reserve | TBD | TBD |
| Liquidity | TBD | TBD |

*Specific allocation percentages will be published prior to mainnet launch.*

### 6.4 Vault Fee Flow

```
Vault depositor earns yield (NAV > high-water mark)
  → BaseVault.evaluateFees() → FeeDistributor
       ├── 50% → ZENT Buyback → burn
       ├── 25% → Protocol Treasury → quant grants, competitions
       ├── 15% → Insurance Fund
       └── 10% → Operations

Vault depositors earn yield in the underlying asset (BTC/ETH/SOL/XRP).
Vault depositors do NOT earn ZENT. ZENT is not a yield-bearing asset.
```

### 6.5 Quant Reward Flow (Legally Clean)

```
Protocol treasury (from vault fees)
  → Quant Signal Competitions
  → Volatility Bracket prizes
  → Top-leaderboard weekly rewards

Quant rewards are grants from the treasury, not transfers of vault depositor funds.
This breaks the securities link: quants are not running a fund.
They are receiving grants for research quality, similar to academic grants.
```

---

## 7. Signal Flow

### 7.1 Signal Submission

1. Quant generates signal (any supported asset: BTC-PERP, ETH-PERP, etc.)
2. Quant signs with EIP-712: `Sign(provider, assetClass, assetId, direction, confidence, nonce, expiresAt)`
3. Quant stakes ZENT on the signal (the **Conviction Stake**)
4. Signed signal submitted to `SignalRegistry`
5. Event `SignalSubmitted` emitted → indexed by engine

### 7.2 Signal Scoring (Every 4 Hours)

1. Epoch closes (every 4 hours)
2. ScoringOracle fetches Chainlink settlement prices
3. For each active signal: compute `accuracyBps` (how close predicted direction was to realized)
4. Apply Numerai-style payout formula: `payout_factor × stake × 0.3`, clipped to [-1.7%, +5.0%]
5. `EpochScoring.applyPayout()` → slash or reward the quant's staked ZENT

### 7.3 Signal Attribution to Vault Fills

1. Each Hyperliquid fill is recorded in `hl_user_fills` with timestamp
2. Each `TradeSignalExecuted` event recorded in `execution_attempts` with tx hash
3. Attribution engine links fills to signals by:
   - Time window: fill within N blocks of signal timestamp
   - Asset match: fill coin matches signal assetId
   - Direction match: fill side matches signal direction
4. Ghost Portfolio computes: for each attributed fill, what would have been the return?

### 7.4 Signal Resolution States

```
Submitted → Active → Resolved
                      ↘ Challenged → Slashed
```

---

## 8. Ghost Portfolio & Attribution

### 8.1 The Three-Line Chart

The Ghost Portfolio dashboard shows three simultaneous lines:

```
Line 1 — HOLD:
  Starting balance = amount of BTC that would equal today's vault NAV if held
  Updated daily from Chainlink BTC price feed

Line 2 — GHOST (Follow Signals):
  For each attributed fill: apply same size, same direction, same entry
  Compounded return over the same time period

Line 3 — ACTUAL (Vault Performance):
  Real vault NAV per share, updated from BaseVault.getNavPerShare()
```

### 8.2 Attribution Rules

| Condition | Rule |
|---|---|
| Time window | Fill within 2 hours of signal timestamp |
| Asset match | Fill `coin` matches signal `assetId` |
| Direction match | Fill `side` (Buy/Sell) matches signal `direction` |
| Size | Fill `sz` attributed proportionally to signal `confidence` |
| Expiry | Signal expired before fill → not attributed |

### 8.3 ZENTORY Score Formula

```
ZENTORY Score = (
  vault_loyalty_score × 0.25 +
  quant_performance_score × 0.25 +
  stake_age_score × 0.20 +
  network_participation_score × 0.15 +
  social_engagement_score × 0.15
) × 1000

vault_loyalty_score: 0–1 (0 = new depositor, 1 = 2+ year holder)
quant_performance_score: 0–1 (weighted accuracy × conviction)
stake_age_score: 0–1 (veZENT / max possible veZENT)
network_participation_score: 0–1 (followers + following normalized)
social_engagement_score: 0–1 (cards shared + tips given)
```

---

## 9. Legal Framework

### 9.1 ZENT as a Utility Token

ZENT is classified as a **utility token**, not a security, based on the following design choices:

- ZENT does not entitle holders to revenue share from vault operations
- ZENT does not represent ownership in ZENTORY Labs or the protocol
- ZENT is required to access protocol functions (signal submission, vault access tiers, governance)
- ZENT price appreciation, if any, reflects protocol utility demand, not enterprise value

### 9.2 Quant Rewards as Treasury Grants

Quant signal rewards are **grants from the protocol treasury**, not transfers of vault depositor funds. This is analogous to:

- Academic research grants (funded by institution, not by the people the research might benefit)
- Kaggle competition prizes (prizes from sponsors, not from competitors' entry fees being redistributed)

This design intentionally avoids the securities classification risk of "quants earn from vault profit."

### 9.3 Geographic Restrictions

The following are blocked at the application layer for users accessing `app.zentorylabs.com`:

- United States (SEC regulatory uncertainty)
- European Union (MiCA compliance TBD)
- Any jurisdiction where ZENT token or vault yield products are classified as regulated instruments

### 9.4 Required Disclaimers

All marketing materials, the frontend UI, and the ZENTORY Score card display:

```
ZENTORY is experimental software. Past performance of any quant or vault
is not indicative of future results. Cryptocurrency trading involves
substantial risk of loss. This is not investment advice.
```

---

## 10. Smart Contract Security

### 10.1 Audit Status

| Audit Type | Date | Status |
|---|---|---|
| Internal / Self-Audit | April 2026 | Complete |
| Slither Static Analysis | April 2026 | Clean |
| Formal Third-Party Audit | TBD | Planned pre-mainnet |

### 10.2 Key Security Features

**EIP-712 Signal Signatures:**
Every signal is signed by the quant's wallet using EIP-712 structured data signing. Signatures are verified on-chain and cannot be tampered with after submission.

**Nonce Mechanism:**
Each quant has an on-chain `providerNonce` that increments with every signal. A reused nonce invalidates the signature. This prevents replay attacks and signal tampering.

**Automated Slashing (No Human Discretion:**
`EpochScoring.applyPayout()` is the sole mechanism for slashing. No human can selectively slash a quant. `EpochScoring` holds the `GOVERNOR_ROLE` on `ZENTStaking`.

**Non-Custodial Vault:**
User funds are held in ERC-4626 vault contracts. The protocol never holds user private keys. Signal routing contracts have limited mandate over vault balances only.

**Circuit Breaker:**
`BaseVault` implements an automatic circuit breaker triggered on NAV drawdown. Anyone can call `checkCircuitBreaker()` — it is not access-controlled.

### 10.3 Upgrade Strategy

**Non-upgradeable (immutable):**
- `SignalRegistry` — signal history must be permanently verifiable
- `ZENT` token — fixed supply is a core promise
- `BaseVault` core logic — vault rules must be immutable post-deployment

**Upgradeable (ERC-1967 Proxy):**
- `EpochScoring` — adjust epoch duration, slash/reward caps
- `ZENTStaking` — adjust minimum stake
- `FeeDistributor` — adjust fee allocations

---

## 11. Governance

### 11.1 What is Governed

| Parameter / Action | Governance Required |
|---|---|
| Epoch duration | Simple majority |
| Max slash / reward BPS | Simple majority |
| New vault asset listing | Simple majority |
| Treasury grant allocation | Simple majority |
| Smart contract upgrades | 66% supermajority |

### 11.2 Voting Mechanics

Voting weight derives from `veZENT` balance (not raw ZENT). A voter with 1,000 ZENT locked for 365 days has `veBalance = 500`. Longer-term stakers have more voting power, aligning governance with protocol long-term health.

All governance actions pass through a **48-hour timelock** before execution.

---

## 12. Roadmap

| Milestone | Target | Status |
|---|---|---|
| Testnet contract deployment | Apr 2026 | Complete |
| Hyperliquid fill indexing pipeline | May 2026 | Complete |
| Supabase hybrid execution tables + RLS | May 2026 | Complete |
| Vault NAV tracking + Ghost Portfolio engine | Q3 2026 | Planned |
| ZENTORY Score card generator | Q3 2026 | Planned |
| Conviction Score leaderboard | Q3 2026 | Planned |
| Auto-Follow (copy trading) | Q4 2026 | Planned |
| Volatility Brackets (season 1) | Q4 2026 | Planned |
| Formal third-party audit | Q4 2026 | Planned |
| Mainnet deployment | Q4 2026 | Planned |
| Bug bounty program | Q4 2026 | Planned |

---

## 13. Team & Legal

*This section to be completed by founders and reviewed by qualified legal counsel prior to mainnet launch and any public token distribution.*

### 13.1 Team

**To be disclosed.** The ZENTORY Labs team is currently pseudonymous. Prior to mainnet, the following will be published:

- Team members' names, roles, and verified background
- Advisor names and affiliations
- History of previous projects

### 13.2 Legal Structure (Recommended)

| Entity | Jurisdiction | Purpose |
|---|---|---|
| Protocol Foundation | Cayman Islands | Token issuance, governance, non-operational |
| Operations Company | Delaware, USA (or appropriate) | Development, employment, operations |

### 13.3 Key Legal Considerations

1. **ZENT Token:** Legal opinion required on utility vs. security classification prior to any public sale.
2. **Investment Advice:** Quant signal platform is structured as informational research, not investment management. No managed account relationships.
3. **AML/KYC:** KYC/AML compliance required depending on jurisdiction and token classification.
4. **Geo-blocking:** Implemented at the application layer for US, EU, and other restricted jurisdictions.

### 13.4 Disclaimer

**This whitepaper is provided for informational purposes only and does not constitute:**

- An offer to sell or solicitation to buy any security or investment
- Financial, legal, tax, or investment advice
- An endorsement of any investment strategy or trading approach
- A guarantee of future performance of any signal provider or vault

**Past performance of any signal provider or vault is not indicative of future results. Cryptocurrency trading and signal provision involve substantial risk of loss.**

---

## Appendix A: Contract Interface Summary

### A.1 ZENT (ERC-20)

```solidity
function CAP() public view returns (uint256)            // 1_000_000_000 * 10**18
function mintForTestnet(address to, uint256 amount)     // Testnet only, one-time
function burn(uint256 amount) external
function burnFrom(address account, uint256 amount) external
```

### A.2 SignalRegistry

```solidity
function submitSignal(
    address provider, SignalTypes.AssetClass assetClass, bytes32 assetId,
    int256 direction, uint256 confidence, uint256 expiresAt, bytes signature
) external returns (bytes32 signalId)

function submitSignalBatch(SignalTypes.Signal[] calldata batch) external returns (bytes32[] memory ids)
function resolveSignals(bytes32[] calldata signalIds, uint256[] calldata accuraciesBps) external
function getSignal(bytes32 signalId) external view returns (SignalTypes.Signal memory)
function providerNonce(address provider) external view returns (uint256)
function signalExists(bytes32 signalId) external view returns (bool)
```

### A.3 EpochScoring

```solidity
function checkUpkeep(bytes calldata) external view returns (bool upkeepNeeded, bytes memory performData)
function performUpkeep(bytes calldata performData) external
function settleEpoch() public
function applyPayout(bytes32 signalId) public returns (int256 payout)
function setAccuracy(bytes32 signalId, uint256 accuracyBps) external
function setAccuracyBatch(bytes32[] calldata signalIds, uint256[] calldata accuraciesBps) external
function setPriceFeed(bytes32 assetId, address feed) external
function getPrice(bytes32 assetId) public view returns (int256 price, uint8 decimals)
```

### A.4 ZENTStaking

```solidity
function stake(uint256 amount, uint64 lockDuration) external returns (uint64 lockEnd)
function increaseAmount(uint256 amount) external
function extendLock(uint64 newLockDuration) external returns (uint64 newLockEnd)
function withdraw() external
function veBalance(address user) external view returns (uint256)
function hasAccess(address user) external view returns (bool)
function stakedBalance(address user) external view returns (uint256)
function lockEndOf(address user) external view returns (uint64)
function getProviderStake(address provider) external view returns (uint256)
function slash(address provider, uint256 amount) external onlyRole(GOVERNOR_ROLE)
function reward(address provider, uint256 amount) external onlyRole(GOVERNOR_ROLE)
```

### A.5 BaseVault (zBTC, zETH, zSOL, zXRP)

```solidity
function deposit(uint256 assets, address receiver) public returns (uint256)
function mint(uint256 shares, address receiver) public returns (uint256)
function evaluateFees() external onlyRole(KEEPER_ROLE)
function claimFees() external nonReentrant returns (uint256 claimed)
function recordTrade(int8 direction, uint256 size, uint256 entryPrice) external onlyRole(KEEPER_ROLE)
function closePosition() external onlyRole(KEEPER_ROLE)
function activateCircuitBreaker(string calldata reason) external onlyRole(RISK_COUNCIL_ROLE)
function deactivateCircuitBreaker() external onlyRole(DEFAULT_ADMIN_ROLE)
function checkCircuitBreaker() external
function getNavPerShare() public view returns (uint256)
```

### A.6 FeeDistributor

```solidity
function accumulate(address vault, uint256 amount) external
function distribute(address vault) external
function triggerBuyback(address[] calldata path) external onlyRole(GOVERNOR_ROLE)
function withdrawTo(address recipient, uint256 amount, uint8 poolId) external onlyRole(GOVERNOR_ROLE)
// POOL_BUYBACK=0, POOL_GP_ENGINE=1, POOL_INSURANCE=2, POOL_TREASURY=3
```

---

## Appendix B: Glossary

| Term | Definition |
|---|---|
| **AccuracyBps** | Basis-point accuracy score (0–10000) for a signal at epoch settlement. 10000 = perfect prediction. |
| **Conviction Score** | ZENT staked on a single signal. Higher conviction = more skin in the game. |
| **Epoch** | A 4-hour scoring window. Signals submitted during an epoch are settled at the epoch's end. |
| **Ghost Portfolio** | A simulated portfolio showing what following quant signals would have returned vs. HOLD vs. actual vault. |
| **GHOST line** | The Ghost Portfolio's return line on the three-line vault chart. |
| **HOLD line** | The baseline return line for simply holding the asset (BTC/ETH/SOL/XRP). |
| **ACTUAL line** | The real vault NAV per share return line. |
| **Signal Arena** | The social layer of ZENTORY: conviction-ranked quants, auto-follow, ghost portfolio, volatility brackets. |
| **veZENT** | Vote-escrowed ZENT. Time-weighted staking balance used for governance voting weight. Decays linearly to zero at lock expiry. |
| **ZENTORY Score** | A 0–1000 reputation score for any wallet, based on vault loyalty, quant performance, stake age, network, and social engagement. |
| **Volatility Bracket** | A 48-hour competitive quant tournament triggered by >3% BTC moves in 1 hour. |

---

*Document version: 2.0 | Last updated: May 2026 | ZENTORY Labs Core Development Team*
