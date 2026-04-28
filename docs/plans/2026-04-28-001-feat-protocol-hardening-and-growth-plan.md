---
title: "ZENT Protocol Hardening, Growth & Institutional Readiness"
type: feat
status: active
date: 2026-04-28
deepened: 2026-04-28
---

# ZENT Protocol Hardening, Growth & Institutional Readiness

## Overview

ZENT is a multi-asset quant signal exchange on HyperEVM — providers stake ZENT to submit trading signals, subscribers pay ZENT to access them, and stakers earn yield from subscription revenue. The protocol is deployed on testnet with functional smart contracts and a working frontend. This plan addresses the critical gaps between the current state and a product that investors, professional quants, and retail users can trust and adopt.

---

## Problem Frame

The protocol has three structural weaknesses that block institutional and mass-market adoption:

1. **Security** — Smart contracts are unaudited, which means no serious investor or fund will touch them.
2. **Onboarding friction** — Subscribing requires owning ZENT, connecting a wallet, and signing transactions. The average retail trader uses Robinhood and has never heard of a wallet.
3. **Trust deficit** — Signal performance is shown as mock data. Professional quants and subscribers need auditable, real-time, on-chain verified track records.

Additionally, three foundational capabilities are missing for the protocol to operate autonomously:
- **Epoch automation** — Scoring and payout distribution currently require manual keeper calls.
- **Provider infrastructure** — There's no portal for quants to submit signals, manage API keys, or track their performance.
- **Analytical foundation** — No schema exists to track epoch history, per-provider analytics, or subscription events needed for the leaderboard and analytics dashboard.

---

## Scope Boundaries

**In scope:**
- Smart contract vulnerability review and remediation (self-audit prep for professional audit)
- Stripe subscription integration for fiat onboarding
- Wallet UX improvements (WalletConnect + Coinbase Wallet + one-click connect)
- Public provider leaderboard page
- Per-provider signal analytics dashboard
- Epoch automation keeper script
- Supabase schema extensions (epoch history, provider analytics, subscription events, audit log)
- Technical whitepaper

**Explicitly out of scope:**
- Professional audit engagement (this plan prepares the code for one)
- Regulatory compliance work (legal memo only — actual compliance counsel deferred)
- Credit card data storage / PCI compliance (handled by Stripe)
- Mainnet deployment
- Token listing on exchanges

### Deferred to Follow-Up Work

- **Multi-asset data feeds** — Real-time equity/forex/commodity price feeds require Bloomberg/Refinitiv licenses and are deferred until regulatory clarity is established. The multi-asset marketing claim must be removed or qualified until then.
- **Mainnet deployment** — This plan targets testnet-only production-readiness.
- **Professional audit engagement** — After self-audit prep (U1), engage Trail of Bits, OpenZeppelin, or Spearbit for formal audit.
- **Compliance/legal counsel** — The regulatory review (U10) produces a memo, not legal advice. Actual RIA/IA registration or exemptions must be handled by licensed counsel.

---

## Key Technical Decisions

- **Stripe over direct card processing** — Avoids PCI compliance burden. Use Stripe Checkout + webhook handlers. Subscription state is managed in Supabase (Stripe is the payment processor, not the source of truth).
- **Keeper script over Chainlink Automation for epoch scoring** — `checkUpkeep`/`performUpkeep` exist in `EpochScoring` but the Chainlink Automation registrar is not yet configured on testnet. A cron-style keeper script (Node.js) is the pragmatic interim solution; it can be replaced with Chainlink Automation without contract changes.
- **Supabase as source of truth for analytics** — On-chain signal evaluation (via `SignalRegistry` events) is the authoritative record. Supabase provides fast reads, historical queries, and aggregation that the chain cannot efficiently serve. Both are kept in sync via the keeper script.
- **Leaderboard and analytics are read-only views** — No writes from the browser. All data flows: keeper script → Supabase, keeper script → `EpochScoring.setAccuracy()`, keeper script → `SignalRegistry.resolveSignals()`.
- **WalletConnect v2 via wagmi** — Already using wagmi v2 which has WalletConnect v2 built in. Coinbase Wallet will be added as a connector.

---

## High-Level Technical Design

### Keeper Architecture (U8)

```
Every 4 hours (cron):
  keeper/
    index.ts          ← Cron entry: calls ScoringOracle
    ScoringOracle.ts  ← Queries Supabase for active signals in epoch,
                        computes accuracy, calls EpochScoring.setAccuracy(),
                        then EpochScoring.settleEpoch()
                        and Supabase.epoch_history INSERT
```

The keeper is a Node.js script (not a Solidity contract) that:
1. Reads `SignalRegistry.SignalSubmitted` events from the last 4 hours via HyperEVM RPC
2. Computes accuracy per signal (compares direction to actual price change from Chainlink feeds)
3. Calls `EpochScoring.setAccuracy()` for each signal
4. Calls `EpochScoring.applyPayout()` for each signal
5. Inserts into `Supabase.epoch_history` and updates `Supabase.provider_analytics`

### Stripe Subscription Flow (U2)

```
Browser:
  POST /api/subscribe/create-checkout
    → Creates Stripe Checkout Session
    → Returns { checkoutUrl }

Stripe:
  → Redirects user to checkoutUrl
  → On success: redirects to /subscribe/success?session_id=xxx

Webhook (/api/stripe/webhook):
  stripe.events.checkout.session.completed
    → Insert into Supabase.subscriptions
    → Insert into Supabase.subscription_events
    → Return 200

Browser (success page):
  GET /subscribe/success?session_id=xxx
    → Display "Subscription activated"
    → Show ERC-6932 subscription token (fetch from SubscriptionVault.hasAccess())
```

### Provider Portal (U7)

```
Frontend: app/provider-portal/
  api-keys/page.tsx     ← Generate + revoke API keys (stored hashed in Supabase)
  dashboard/page.tsx    ← Signal submission form, performance charts, payout history
  submissions/page.tsx  ← History of submitted signals with accuracy/payout status

Backend: app/api/provider/
  route.ts              ← POST: create signal (validates API key, calls SignalRegistry)
  api-keys/route.ts    ← POST: create key, DELETE: revoke key
  analytics/route.ts   ← GET: per-provider stats from Supabase
```

---

## Implementation Units

- [ ] U1. **Smart Contract Self-Audit & Vulnerability Remediation**
- [ ] U2. **Stripe Subscription Integration**
- [ ] U3. **Wallet UX Overhaul (WalletConnect + Coinbase + Error States)**
- [ ] U4. **Public Provider Leaderboard Page**
- [ ] U5. **Signal Performance Analytics Dashboard**
- [ ] U6. **Technical Whitepaper**
- [ ] U7. **Provider Portal (API Keys + Signal Submission + Analytics)**
- [ ] U8. **Epoch Automation Keeper Script**
- [ ] U9. **Supabase Schema Extensions**
- [ ] U10. **Regulatory Review Memo**

---

- [ ] U1. **Smart Contract Self-Audit & Vulnerability Remediation**

**Goal:** Identify and fix all exploitable vulnerabilities in the deployed smart contracts so the code is ready for a professional audit engagement.

**Requirements:** R1 (contracts are safe for testnet use), R2 (no reentrancy, overflow, access control, or front-running vulnerabilities in critical paths)

**Dependencies:** None

**Files:**
- Modify: `contracts/src/signals/SignalRegistry.sol`
- Modify: `contracts/src/signals/EpochScoring.sol`
- Modify: `contracts/src/signals/SubscriptionVault.sol`
- Modify: `contracts/src/staking/ZENTStaking.sol`
- Create: `contracts/scripts/audit/self_audit_findings.md`
- Create: `contracts/scripts/audit/remediation_checklist.md`

**Approach:**

Perform a systematic vulnerability review across all contracts following the OWASP Smart Contract Top 10 and Consensys Diligence checklist. Focus on:

1. **Reentrancy** — `SubscriptionVault.subscribe()` calls `safeTransferFrom()` before state updates. Move all state mutations before external calls (Checks-Effects-Interactions pattern). Also check `cancelSubscription()` and `renewSubscription()`.
2. **Integer overflow/underflow** — Solidity 0.8.x has built-in overflow checks, but verify all arithmetic in `EpochScoring.applyPayout()` where `int256(rawPayout) * int256(stake)` could theoretically overflow in extreme scenarios.
3. **Access control** — `EpochScoring.setAccuracy()` and `setAccuracyBatch()` have no access control. Anyone can set accuracy to 10000 for their own signals. Restrict to `msg.sender == scoringOracle` (a governance-set address). Add `onlyScoringOracle` modifier.
4. **Front-running** — `SignalRegistry.submitSignal()` exposes the provider's pending signal before inclusion. The signature provides some protection, but the nonces should be checked before the signature verification to prevent griefing.
5. **Denial of Service** — `SubscriptionVault.hasAccess()` loops through all subscriber tokens. With many subscriptions this becomes gas-expensive. Add a `latestExpirationOf[subscriber]` cache that is updated on subscribe/renew/cancel.
6. **Signature replay** — `SignalRegistry` stores nonces but does not check if a signature was already used (the nonce check exists, but verify it is checked BEFORE signature recovery, not after).
7. **EpochScoring._countActiveSignals()** always returns 0 — this is a critical placeholder that breaks the entire scoring mechanism. It must be replaced with a Subgraph-based or event-log-based implementation.
8. **Missing events** — `setAccuracy()` and `setAccuracyBatch()` do not emit events that an indexer could use. Add `AccuracySet` events with the epoch context.
9. **Gas limits** — `submitSignalBatch()` iterates over an unbounded array. Add a maximum batch size constant (e.g., 100) and enforce it.
10. **UUPS proxy pattern** — Contracts are not upgradeable. For a protocol holding value, this is a risk. Document whether upgradeability is desired and if so, implement ERC-1967 proxy.

Document all findings in `contracts/scripts/audit/self_audit_findings.md` with severity (Critical/High/Medium/Low/Informational), description, affected code location, and recommended fix.

**Test scenarios:**
- Happy path: Submit a batch of 50 signals — all succeed within gas limit
- Edge case: Submit batch with 101 signals — reverts with MaxBatchSizeExceeded
- Edge case: Call setAccuracy() from non-oracle address — reverts with AccessControl
- Edge case: subscribe() with exact ZENT balance — succeeds, no overflow
- Edge case: subscribe() when ZENT balance is 1 wei short — reverts with InsufficientZENT
- Error path: Cancel subscription that was already cancelled — reverts with notOwnerOfToken
- Error path: renewSubscription() on expired subscription — extends from block.timestamp
- Integration: Full epoch lifecycle — signals submitted, keeper sets accuracy, settleEpoch() fires, payouts applied correctly

**Verification:**
- All Critical and High findings from self-audit are fixed or documented
- forge test passes with all existing tests
- New tests for access control on setAccuracy() pass
- Batch size limit is enforced and tested

---

- [ ] U2. **Stripe Subscription Integration**

**Goal:** Enable retail users to subscribe to ZENT signal tiers using a credit card, with subscription state synced to Supabase and on-chain subscription NFTs minted via a keeper.

**Requirements:** R3 (fiat onboarding for non-crypto users), R4 (Stripe checkout handles payment, Supabase handles subscription state)

**Dependencies:** U9 (Supabase schema extensions must be applied first)

**Files:**
- Create: `frontend/app/api/subscribe/create-checkout/route.ts`
- Create: `frontend/app/api/stripe/webhook/route.ts`
- Create: `frontend/app/subscribe/success/page.tsx`
- Create: `frontend/app/subscribe/success/page.module.css`
- Modify: `frontend/app/subscribe/page.tsx` — add "Pay with Card" button alongside "Connect Wallet + Subscribe"
- Create: `frontend/lib/stripe.ts` — Stripe SDK server-side client
- Create: `supabase/migrations/2026_04_28_002_stripe_subscriptions.sql`

**Approach:**

Install `stripe` npm package. Create a server-side Stripe client using `STRIPE_SECRET_KEY` environment variable. Implement two API routes:

`POST /api/subscribe/create-checkout` — Creates a Stripe Checkout Session with:
- `mode: 'subscription'`
- `line_items` derived from `tierId` query param (tier 0 = $29, tier 1 = $99, tier 2 = $299)
- `success_url` = `/subscribe/success?session_id={CHECKOUT_SESSION_ID}`
- `cancel_url` = `/subscribe`
- `customer_email` pre-fill if wallet connected
- Metadata: `{ tierId, walletAddress (if connected) }`

`POST /api/stripe/webhook` — Handles `checkout.session.completed`:
- Verify Stripe webhook signature using `STRIPE_WEBHOOK_SECRET`
- Extract `tierId` and `walletAddress` from metadata
- If `walletAddress` present: call keeper to mint subscription NFT via `SubscriptionVault.subscribe()`
- Insert into `Supabase.subscriptions` with `stripe_session_id`, `tier_id`, `wallet_address`, `status = 'active'`, `expires_at`
- Insert into `Supabase.subscription_events` with `event_type = 'created'`
- Return HTTP 200 to Stripe

`subscribe/success/page.tsx` — Post-payment landing:
- Read `session_id` from query params
- Call `GET /api/subscribe/status?session_id=xxx` which queries Supabase
- Display: subscription tier, expiration, and "View Subscription NFT" button linking to a wallet-aware view

Add a "Pay with Card" section to `subscribe/page.tsx` with tier cards showing fiat prices alongside the existing ZENT-only flow. Show both options: "Subscribe with Crypto (wallet required)" and "Subscribe with Card (instant, no wallet)".

**Stripe price mapping (configurable via env vars):**
- BASIC (tier 0): $29/month → 100 ZENT/month
- PRO (tier 1): $99/month → 500 ZENT/month
- ELITE (tier 2): $299/month → 2000 ZENT/month

Prices stored in Stripe Dashboard, not hardcoded — makes pricing adjustable without code changes.

**Patterns to follow:**
- `app/api/signals/route.ts` for API route structure
- `app/api/stripe/webhook/route.ts` for webhook signature verification (create this pattern)

**Test scenarios:**
- Happy path: Create checkout session for tier 0 → returns valid checkoutUrl
- Happy path: Webhook receives completed event → inserts into Supabase.subscriptions
- Edge case: Duplicate webhook event (idempotency) — checks `stripe_session_id` unique constraint, ignores duplicate
- Edge case: Invalid webhook signature — returns 400, logs error
- Error path: Unknown tierId in metadata — logs error, does not insert, returns 200 (to prevent Stripe retry storms)
- Integration: Full flow — checkout → payment → webhook → Supabase insert

**Verification:**
- Checkout session created with correct tier price and metadata
- Webhook successfully inserts subscription into Supabase
- Success page renders subscription details from Supabase

---

- [ ] U3. **Wallet UX Overhaul**

**Goal:** Reduce wallet connection friction to under 30 seconds for new users, support WalletConnect v2 and Coinbase Wallet natively, and provide clear error states for common failure modes.

**Requirements:** R5 (one-click wallet connect), R6 (WalletConnect + Coinbase Wallet supported), R7 (clear error messages)

**Dependencies:** None

**Files:**
- Modify: `frontend/components/WalletSelector.tsx`
- Modify: `frontend/components/Providers.tsx` — add Coinbase Wallet connector
- Modify: `frontend/lib/contracts.ts` — add WalletConnect project ID
- Create: `frontend/.env.local` — add `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID`

**Approach:**

**Step 1: Add WalletConnect v2 project ID**

Register at [cloud.walletconnect.com](https://cloud.walletconnect.com) (free tier) to get a Project ID. Add to `.env.local` as `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID`. Configure in `Providers.tsx` wagmi config:

```typescript
import { WalletConnectConnector } from 'wagmi/connectors/walletConnect'
import { CoinbaseWalletConnector } from 'wagmi/connectors/coinbaseWallet'

export function Providers({ children }) {
  const config = useConfig({
    connectors: [
      new WalletConnectConnector({ options: { projectId: process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID } }),
      new CoinbaseWalletConnector({ options: { appName: 'Zentory Protocol' } }),
      // existing injected connectors...
    ]
  })
  // ...
}
```

**Step 2: Improve error states in WalletSelector**

Current implementation silently fails on connection errors. Add:
- Network mismatch detection: if user is on wrong chain, show "Switch to HyperEVM Testnet" button that calls `chain.switch()`
- Connection timeout: after 10s, show "Connection timed out — try again or use a different wallet"
- Rejected connection: show "Connection rejected — please approve in your wallet and try again"
- No wallet installed: detect via `window.ethereum === undefined` and show "No wallet detected — install MetaMask or use WalletConnect"

**Step 3: Persist last connected wallet**

Store `lastConnectedConnectorId` in `localStorage` and auto-reconnect on page load using `useConnect().connect({ connector: lastConnected })` in a `useEffect`.

**Patterns to follow:**
- `components/WalletSelector.tsx` existing pattern
- wagmi v2 documentation for WalletConnectConnector and CoinbaseWalletConnector

**Test scenarios:**
- Happy path: Click "Connect Wallet" → WC modal opens → user approves → address shown
- Happy path: Return to site → auto-connects via persisted connector
- Edge case: User on wrong network → "Switch Network" button appears → switches to HyperEVM
- Edge case: Connection rejected → "Try again" message with retry button
- Edge case: No Ethereum wallet → "Install MetaMask" link displayed
- Error path: WC project ID invalid → graceful fallback to injected wallets only

**Verification:**
- WalletConnect v2 flow completes in < 3 clicks
- Coinbase Wallet appears in connector list
- Wrong network shows clear "Switch to HyperEVM" prompt
- Auto-reconnect works on page revisit within 24h

---

- [ ] U4. **Public Provider Leaderboard Page**

**Goal:** Display a real-time ranked leaderboard of signal providers showing accuracy, total signals, ZENT staked, and epoch history — building trust through transparent, auditable performance data.

**Requirements:** R8 (public leaderboard with real-time data), R9 (per-epoch performance history)

**Dependencies:** U8 (keeper must be running to populate epoch_history), U9 (Supabase schema)

**Files:**
- Create: `frontend/app/leaderboard/page.tsx`
- Create: `frontend/app/api/leaderboard/route.ts` — server-side aggregation
- Create: `frontend/app/api/leaderboard/[provider]/route.ts` — per-provider epoch history

**Approach:**

**`GET /api/leaderboard`** aggregates from `provider_stats` + `epoch_history`:
```sql
SELECT
  ps.provider,
  ps.total_signals,
  ps.resolved_signals,
  ps.avg_accuracy_bps,
  ps.total_payout_zent,
  ps.current_rank,
  ps.last_signal_at,
  eh.epoch_count,
  eh.best_epoch_bps,
  eh.worst_epoch_bps
FROM provider_stats ps
LEFT JOIN (
  SELECT provider,
    COUNT(*) as epoch_count,
    MAX(avg_accuracy_bps) as best_epoch_bps,
    MIN(avg_accuracy_bps) as worst_epoch_bps
  FROM epoch_history
  GROUP BY provider
) eh ON eh.provider = ps.provider
ORDER BY ps.current_rank ASC
```

**`app/leaderboard/page.tsx`** renders:
- Top 3 providers with trophy icons (gold/silver/bronze)
- Ranked table with: Rank, Provider address (shortened), Total Signals, Accuracy (%), ZENT Earned, Last Signal
- Sparkline chart per provider showing accuracy over last 10 epochs
- Filter by asset class (Crypto / Equity / Forex / Commodity)
- "Your Rank" section if wallet connected (shows their position)
- Real-time updates every 60 seconds via SWR/Polling

**Accuracy display:** Convert `avg_accuracy_bps / 100` → percentage. Color-code: green ≥65%, yellow 55–64%, red <55%.

**Patterns to follow:**
- `app/markets/page.tsx` for page layout and component structure
- `LiveSignalFeedWrapper.tsx` for SWR polling pattern

**Test scenarios:**
- Happy path: Leaderboard loads with ranked providers sorted by current_rank
- Edge case: Provider with 0 signals — shows "No signals yet" with muted styling
- Edge case: Provider rank changes between page loads — animated rank change indicator
- Edge case: Filter by Crypto — only shows providers who submitted crypto signals

**Verification:**
- Page loads with provider data from Supabase
- Top 3 providers display with trophy styling
- Real-time polling updates data without page refresh

---

- [ ] U5. **Signal Performance Analytics Dashboard**

**Goal:** Provide subscribers and potential subscribers with detailed per-signal and aggregate performance analytics — the proof that the signals work.

**Requirements:** R10 (per-signal accuracy tracking), R11 (win rate by asset class), R12 (Sharpe-like score)

**Dependencies:** U9 (Supabase schema), U8 (keeper populating signal_scores)

**Files:**
- Create: `frontend/app/analytics/page.tsx` — main analytics dashboard
- Create: `frontend/app/api/analytics/overview/route.ts` — aggregate stats
- Create: `frontend/app/api/analytics/provider/[provider]/route.ts` — per-provider breakdown
- Create: `frontend/app/api/analytics/markets/route.ts` — per-market breakdown

**Approach:**

**`GET /api/analytics/overview`** returns:
- Total signals (all time)
- Overall accuracy (weighted average by veBalance)
- Win rate (% of signals with accuracy > 5000 bps)
- Best performing asset class
- Worst performing asset class
- Total ZENT distributed as payouts
- Average ZENT per signal

**`GET /api/analytics/provider/[provider]`** returns per-provider:
- Total signals, resolved signals
- Accuracy distribution histogram (5 buckets: 0-2000, 2000-4000, 4000-6000, 6000-8000, 8000-10000 bps)
- Accuracy over time (line chart data: last 20 epochs)
- Accuracy by asset class (bar chart)
- Cumulative ZENT earned/lost
- Best signal, worst signal

**`GET /api/analytics/markets`** returns per-market (e.g., BTC-PERP, ETH-PERP):
- Total signals
- Average accuracy
- Direction breakdown (% LONG vs SHORT)
- Provider count

**`app/analytics/page.tsx`** renders:
- Summary stat cards (total signals, avg accuracy, win rate, total payouts)
- Accuracy over time chart (line chart, last 20 epochs)
- Asset class performance comparison (bar chart by asset class)
- Recent signals table with accuracy scores

Use a charting library (Chart.js or Recharts). For MVP, implement a simple SVG-based sparkline/chart directly without a heavy library to avoid bundle size impact.

**Patterns to follow:**
- `app/markets/page.tsx` for stat card layout
- `app/api/markets-signals/route.ts` for API route structure

**Test scenarios:**
- Happy path: Analytics page loads with aggregate stats from Supabase
- Edge case: No signals yet → shows "No data yet" state with "Submit the first signal" CTA
- Edge case: Provider with 1 signal → histogram shows single bar
- Edge case: Accuracy over time — handles gaps where provider had no signals in certain epochs

**Verification:**
- Charts render with real data from Supabase
- Provider filter updates all charts simultaneously
- Time range selector (7d / 30d / All) correctly filters data

---

- [ ] U6. **Technical Whitepaper**

**Goal:** Produce a comprehensive technical document suitable for sharing with investors, auditors, and serious quant teams — explaining the full protocol architecture, tokenomics, economic security model, and risk parameters.

**Requirements:** R13 (technical whitepaper exists), R14 (covers tokenomics, signal flow, governance, risk)

**Dependencies:** U1 (self-audit findings must be complete)

**Files:**
- Create: `ZentoryToken/docs/whitepaper.md`
- Create: `ZentoryToken/docs/whitepaper.pdf` (generated via markdown-to-PDF tool)

**Approach:**

Structure the whitepaper as follows:

1. **Executive Summary** — What ZENT is, the problem it solves, the market opportunity (quant signal market size, DeFi market size)
2. **Protocol Architecture** — High-level diagram showing SignalRegistry → EpochScoring → ZENTStaking → FeeDistributor → ZentGovernor flow
3. **Token Economics** — ZENT supply schedule, token utility (staking for providers, subscription payments, governance), fee distribution (%% to stakers, %% to treasury, %% burned), staking APR model
4. **Signal Flow** — Step-by-step walkthrough of a signal from submission to payout, including EIP-712 signing, nonce management, epoch scoring, Numerai-style payout formula
5. **Multi-Asset Expansion** — How the protocol extends to equity, forex, commodities — data feed requirements, regulatory framework, asset class bitmap in SubscriptionVault
6. **Smart Contract Security** — Summary of audit status, known limitations, upgrade strategy, bug bounty program
7. **Governance** — What ZentGovernor controls (fee tiers, epoch duration, new asset class addition, treasury spend), voting mechanics, voter incentives
8. **Risk Parameters** — MAX_PENALTY_BPS, MAX_REWARD_BPS, MIN_STAKE, EPOCH_DURATION — rationale for each
9. **Roadmap** — Testnet → Mainnet → Multi-asset → Institutional partnerships → Decentralized governance
10. **Team** — (placeholder section for legal structure, founders, advisors)

**Technical depth required:** Should be detailed enough that a solidity auditor can understand the economic invariants that need to hold, and a quant can understand exactly how their signals are scored.

**Patterns to follow:**
- Numerai whitepaper for economic model framing
- Ellipsis Labs / Mango Markets documentation for technical DeFi structure

**Verification:**
- Whitepaper is complete (10 sections)
- All contract addresses are accurate for testnet
- Math in payout formula is verified against EpochScoring.applyPayout()

---

- [ ] U7. **Provider Portal**

**Goal:** Give signal providers a self-service interface to manage API keys, submit signals, and monitor performance — reducing the barrier for quants to join the network.

**Requirements:** R15 (API key management), R16 (signal submission interface), R17 (performance analytics)

**Dependencies:** U9 (Supabase schema for api_keys, api_key_requests table)

**Files:**
- Create: `frontend/app/provider-portal/page.tsx` — main portal landing
- Create: `frontend/app/provider-portal/api-keys/page.tsx` — key management
- Create: `frontend/app/provider-portal/dashboard/page.tsx` — performance overview
- Create: `frontend/app/provider-portal/submissions/page.tsx` — signal history
- Create: `frontend/app/api/provider/route.ts` — signal submission endpoint
- Create: `frontend/app/api/provider/api-keys/route.ts` — key CRUD
- Create: `frontend/app/api/provider/analytics/route.ts` — provider analytics
- Create: `supabase/migrations/2026_04_28_003_provider_portal.sql`

**Approach:**

**API Key Management:**

`supabase/migrations/2026_04_28_003_provider_portal.sql`:
```sql
CREATE TABLE public.api_keys (
  id           bigserial PRIMARY KEY,
  provider     text NOT NULL,
  key_hash     text NOT NULL UNIQUE,  -- sha256 of actual key, stored hashed
  key_prefix   text NOT NULL,          -- first 8 chars for identification
  label        text,
  created_at   bigint NOT NULL DEFAULT (EXTRACT(EPOCH FROM NOW()))::BIGINT,
  last_used_at bigint,
  is_active    boolean DEFAULT true,
  UNIQUE(provider, label)
);

CREATE INDEX idx_api_keys_provider ON public.api_keys(provider);
```

**Signal Submission (`POST /api/provider`):**
- Validate `x-api-key` header against hashed keys in Supabase
- Verify key is active and not expired
- Parse signal payload: `{ assetClass, assetId, direction, confidence, expiresAt }`
- Validate: direction in [-10000, 10000], confidence in [1, 10000], expiresAt > now
- Call `SignalRegistry.submitSignal()` via ethers.js/viem
- Return signalId

**API Keys CRUD (`/api/provider/api-keys`):**
- `POST` — generate random API key, store SHA256 hash, return plaintext key once to user (never stored plaintext)
- `DELETE` — soft-delete (set is_active = false)

**Provider Portal Pages** (all require wallet connection):
- API Keys: list active/revoked keys, create new key, revoke existing
- Dashboard: accuracy over time chart, total ZENT earned, current veBalance, rank
- Submissions: paginated table of all submitted signals with status (Active/Resolved), accuracy, payout

**Patterns to follow:**
- `app/api/signals/execute/route.ts` for signal submission pattern
- `app/leaderboard/page.tsx` for chart styling

**Test scenarios:**
- Happy path: Generate API key → key appears in list, plaintext shown once
- Happy path: Submit signal via API key → signal recorded in Supabase, tx confirmed
- Edge case: Submit with revoked API key → 401 response
- Edge case: Submit with expired subscription → 403 response (keeper rejects)
- Error path: Submit with invalid direction value → 400 validation error

**Verification:**
- API key created and usable for signal submission
- Signal appears in Supabase.signals and on-chain
- Revoked key cannot submit signals

---

- [ ] U8. **Epoch Automation Keeper Script**

**Goal:** Automate the 4-hour epoch scoring and payout distribution cycle so the protocol operates without manual intervention.

**Requirements:** R18 (keeper script runs every 4 hours), R19 (accuracy computed from Chainlink price feeds), R20 (payouts applied on-chain and recorded in Supabase)

**Dependencies:** U9 (Supabase schema), U1 (access control on setAccuracy)

**Files:**
- Create: `contracts/keeper/ScoringOracle.ts` — TypeScript keeper logic
- Create: `contracts/keeper/package.json` — node project with viem, dotenv
- Create: `contracts/keeper/.env.example` — RPC URL, private key, contract addresses
- Create: `contracts/keeper/tsconfig.json`
- Modify: `contracts/src/signals/EpochScoring.sol` — add `onlyScoringOracle` modifier (from U1)
- Create: `contracts/keeper/README.md` — setup and cron instructions

**Approach:**

The keeper is a Node.js script using `viem` for chain interaction. It runs every 4 hours (via cron or systemd timer).

**`ScoringOracle.ts` flow per epoch:**

1. **Discover signals** — Query Supabase for all signals where `expires_at > now AND status = 'Active'` for the current epoch window
2. **Get settlement prices** — For each unique asset in the signals, call `EpochScoring.getPrice(assetId)` to get the settlement price from Chainlink
3. **Compute accuracy** — For each signal:
   - Compare `signal.direction` to realized price change: `accuracyBps = 5000 + (signal.direction / 10000) * (priceChangeBps / 100)`
   - Clip to [0, 10000]
4. **Cache accuracies on-chain** — Call `EpochScoring.setAccuracy(signalId, accuracyBps)` for each signal
5. **Apply payouts** — Call `EpochScoring.applyPayout(signalId)` for each signal
6. **Update Supabase** — Insert into `epoch_history`, update `provider_stats`, insert into `signal_scores`

**Configuration:**
```typescript
const config = {
  rpcUrl: process.env.HYPEREVM_RPC_URL,
  scoringOraclePrivateKey: process.env.SCORING_ORACLE_PRIVATE_KEY,
  signalRegistry: addresses.SignalRegistry,
  epochScoring: addresses.EpochScoring,
  zentStaking: addresses.ZENTStaking,
  chainId: 998,
}
```

**Cron setup (systemd timer recommended for production reliability):**
```
# /etc/systemd/system/zent-keeper.timer
[Timer]
OnBootSec=5min
OnUnitActiveSec=4h
```

**Patterns to follow:**
- `contracts/script/SimulateEndToEnd.s.sol` for chain interaction patterns
- `frontend/scripts/seed_signals.js` for Supabase REST API interaction

**Test scenarios:**
- Happy path: Keeper runs against epoch with 20 signals → all accuracies cached, all payouts applied
- Edge case: Chainlink price feed returns 0 for an asset → skip that signal, log warning
- Edge case: Epoch already settled → keeper skips gracefully
- Edge case: Keeper crashes mid-epoch → re-running picks up from accuracy cache
- Error path: RPC rate limit → exponential backoff retry (3 attempts)

**Verification:**
- Keeper runs without errors against testnet epoch
- accuracies appear in `EpochScoring.accuracyCache()` for all signals
- `provider_stats` updated in Supabase after keeper run
- `epoch_history` contains new row for the settled epoch

---

- [ ] U9. **Supabase Schema Extensions**

**Goal:** Extend the Supabase schema to support the leaderboard, analytics, provider portal, epoch automation, Stripe subscriptions, and audit logging.

**Requirements:** R21 (schema supports all features in U2, U4, U5, U7, U8), R22 (audit log for compliance)

**Dependencies:** None (can run in parallel with other units)

**Files:**
- Create: `supabase/migrations/2026_04_28_004_schema_extensions.sql`

**Approach:**

Run all DDL in a single migration (order matters for foreign key dependencies):

```sql
-- 1. epoch_history — settled epoch records (U8)
CREATE TABLE IF NOT EXISTS public.epoch_history (
  id                  bigserial PRIMARY KEY,
  epoch_id            bigint NOT NULL UNIQUE,
  start_time         bigint NOT NULL,
  end_time           bigint NOT NULL,
  total_signals      bigint NOT NULL DEFAULT 0,
  settled_signals    bigint NOT NULL DEFAULT 0,
  total_payout_zent  numeric(78, 0) NOT NULL DEFAULT 0,
  avg_accuracy_bps   integer,
  settled_at         bigint NOT NULL DEFAULT (EXTRACT(EPOCH FROM NOW()))::BIGINT,
  settled_by         text,
  UNIQUE (epoch_id)
);

-- 2. provider_analytics — denormalized per-epoch provider stats (U5, U8)
CREATE TABLE IF NOT EXISTS public.provider_analytics (
  id                  bigserial PRIMARY KEY,
  provider             text NOT NULL,
  epoch_id            bigint NOT NULL,
  signals_submitted   bigint NOT NULL DEFAULT 0,
  signals_resolved    bigint NOT NULL DEFAULT 0,
  avg_accuracy_bps    integer NOT NULL DEFAULT 0,
  payout_zent         numeric(78, 0) NOT NULL DEFAULT 0,
  rank                integer NOT NULL DEFAULT 0,
  created_at          bigint NOT NULL DEFAULT (EXTRACT(EPOCH FROM NOW()))::BIGINT,
  UNIQUE (provider, epoch_id)
);

CREATE INDEX idx_provider_analytics_provider ON public.provider_analytics(provider);
CREATE INDEX idx_provider_analytics_epoch ON public.provider_analytics(epoch_id);

-- 3. subscription_events — Stripe subscription event log (U2)
CREATE TABLE IF NOT EXISTS public.subscription_events (
  id              bigserial PRIMARY KEY,
  subscription_id bigint,           -- FK to subscriptions.id
  stripe_session_id text UNIQUE,
  wallet_address  text,
  tier_id         integer,
  event_type      text NOT NULL,   -- created, renewed, cancelled, payment_failed
  event_data      jsonb,
  created_at      bigint NOT NULL DEFAULT (EXTRACT(EPOCH FROM NOW()))::BIGINT
);

CREATE INDEX idx_subscription_events_session ON public.subscription_events(stripe_session_id);
CREATE INDEX idx_subscription_events_wallet ON public.subscription_events(wallet_address);

-- 4. api_keys for provider portal (U7)
CREATE TABLE IF NOT EXISTS public.api_keys (
  id              bigserial PRIMARY KEY,
  provider        text NOT NULL,
  key_hash        text NOT NULL UNIQUE,  -- SHA256 of actual key
  key_prefix      text NOT NULL,          -- first 8 chars
  label           text,
  created_at      bigint NOT NULL DEFAULT (EXTRACT(EPOCH FROM NOW()))::BIGINT,
  last_used_at    bigint,
  is_active       boolean DEFAULT true,
  UNIQUE(provider, label)
);

CREATE INDEX idx_api_keys_provider ON public.api_keys(provider);
CREATE INDEX idx_api_keys_hash ON public.api_keys(key_hash);

-- 5. audit_log — immutable compliance log (R22)
CREATE TABLE IF NOT EXISTS public.audit_log (
  id            bigserial PRIMARY KEY,
  actor         text NOT NULL,           -- wallet address or "keeper" or "stripe"
  action        text NOT NULL,           -- signal.submit, subscription.create, payout.apply
  target        text,                    -- signal_id, subscription_id, etc.
  payload       jsonb,                   -- full action data
  tx_hash       text,                    -- on-chain tx hash if applicable
  block_number  bigint,
  created_at    bigint NOT NULL DEFAULT (EXTRACT(EPOCH FROM NOW()))::BIGINT
);

CREATE INDEX idx_audit_log_actor ON public.audit_log(actor);
CREATE INDEX idx_audit_log_action ON public.audit_log(action);
CREATE INDEX idx_audit_log_target ON public.audit_log(target);
CREATE INDEX idx_audit_log_created_at ON public.audit_log(created_at DESC);

-- 6. market_stats — per-market aggregate stats for leaderboard (U4, U5)
CREATE TABLE IF NOT EXISTS public.market_stats (
  id              bigserial PRIMARY KEY,
  market_symbol   text NOT NULL,          -- BTC-PERP, ETH-PERP, AAPL, EURUSD
  asset_class     text NOT NULL,          -- CRYPTO_PERP, EQUITY, FOREX, COMMODITY
  total_signals   bigint NOT NULL DEFAULT 0,
  avg_accuracy_bps integer NOT NULL DEFAULT 0,
  win_rate_bps    integer NOT NULL DEFAULT 0,  -- % of signals with accuracy > 5000
  unique_providers bigint NOT NULL DEFAULT 0,
  last_signal_at  bigint,
  updated_at      bigint NOT NULL DEFAULT (EXTRACT(EPOCH FROM NOW()))::BIGINT,
  UNIQUE(market_symbol)
);

-- 7. webhook_events — idempotency table for Stripe webhooks (U2)
CREATE TABLE IF NOT EXISTS public.webhook_events (
  id                bigserial PRIMARY KEY,
  stripe_event_id   text NOT NULL UNIQUE,
  event_type        text NOT NULL,
  processed_at      bigint NOT NULL DEFAULT (EXTRACT(EPOCH FROM NOW()))::BIGINT,
  payload           jsonb
);
```

**Test scenarios:**
- Happy path: All 7 tables created successfully
- Edge case: Migration re-run → "IF NOT EXISTS" prevents duplicate errors
- Edge case: FK constraint on subscription_events.subscription_id → subscription must exist or insert fails

**Verification:**
- All tables created in Supabase
- RLS policies allow correct read/write patterns
- Indexes support the query patterns used in U4, U5, U7, U8

---

- [ ] U10. **Regulatory Review Memo**

**Goal:** Produce an internal legal/regulatory memo documenting the compliance obligations for ZENT's signal provision business across US, EU, and UK jurisdictions — suitable for sharing with legal counsel and investors.

**Requirements:** R23 (memo covers US SEC/CFTC/FINRA, EU MiCA, UK FCA), R24 (identifies required licenses/exemptions)

**Dependencies:** None (research-only)

**Files:**
- Create: `ZentoryToken/docs/regulatory-memo.md`

**Approach:**

This is a research document, not legal advice. Structure it as:

1. **Executive Summary** — What ZENT does that may trigger regulatory obligations
2. **US Regulatory Framework**
   - SEC: Are ZENT signals "securities advice"? Is ZENT token a security (Howey Test)?
     - Factors: ZENT staking yield comes from others' work (signal providers) → looks like investment contract → security
     - If ZENT is a security: all US investors must be accredited, or must register as RIA
     - Equity signals: providing trading recommendations for equities may require IA registration or exemption (Test_Clark compliance)
   - CFTC: Commodity signals (crypto, forex, commodities)
     - "Commodity Trading Advisor" (CTA) registration may be required
     - exemption: CTA exemption for persons who provide advice incidental to futures trading
   - FINRA: If equity signals provided, "investment advisor" vs "broker-dealer" distinction
3. **EU Regulatory Framework**
   - MiCA (Markets in Crypto-Assets Regulation): ZENT as a utility token — does it need to be classified?
   - MiFID II: If providing investment advice for equities — license required
   - General approach: cross-border service by US/EU providers
4. **UK Regulatory Framework**
   - FCA: Crypto asset business registration requirement
   - Investment advisor registration if providing equity/forex signals to UK persons
5. **Multi-Asset Complications**
   - Equity + forex signals require more licenses than crypto-only
   - Recommended approach: geo-fence equity signals to non-regulated jurisdictions until compliance is established
6. **Red Flags** — What triggers regulator attention:
   - Promising guaranteed returns
   - Marketing to non-accredited retail investors with security signals
   - Operating without required registrations
7. **Recommended Next Steps** — List of concrete actions:
   - Retain securities counsel for Howey Test opinion on ZENT
   - Implement geo-blocking for equity signals in US until IA exemption confirmed
   - Implement KYC on Stripe subscriptions
   - Establish legal entity structure for multi-jurisdiction compliance
8. **Disclaimer** — This memo is research, not legal advice. All regulatory conclusions must be confirmed by licensed counsel.

**Patterns to follow:**
- CoinMarketCap / CoinGecko legal pages for regulatory disclaimers
- Numerai's regulatory disclosures (publicly available)

**Verification:**
- Memo covers US, EU, UK frameworks
- Identifies 3+ specific compliance obligations
- Provides actionable next steps

---

## System-Wide Impact

- **Interaction graph:** U2 (Stripe webhook) writes to `subscriptions` and `subscription_events` tables — must not conflict with manual `SubscriptionVault.subscribe()` calls (which also insert into subscriptions). Ensure both paths write the same schema.
- **Error propagation:** Keeper script failures (U8) mean epochs don't settle — subscribers don't see updated leaderboard, providers don't receive payouts. Must have alerting on keeper failures.
- **State lifecycle risks:** `subscription_status` in Supabase must stay in sync with `SubscriptionVault` on-chain state. If a user cancels on-chain but the keeper hasn't synced, Supabase shows active while chain shows inactive. Mitigate by always reading from on-chain as authoritative for access decisions.
- **Integration coverage:** Full end-to-end test requires: Stripe checkout → webhook → Supabase insert AND keeper → EpochScoring.setAccuracy() → Supabase update. These two flows (payment and scoring) are independent and can be tested separately.
- **Unchanged invariants:** SignalRegistry.submitSignal() signature scheme unchanged. SubscriptionVault tier pricing unchanged. ZENTStaking lock mechanics unchanged.

---

## Risks & Dependencies

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Stripe webhook idempotency failures cause duplicate subscriptions | Medium | High | Use `stripe_session_id` unique constraint as idempotency key; webhook handler checks before insert |
| Keeper script runs before Chainlink price feeds are configured | High | High | Keeper logs warning and skips assets without feeds; price feed registration is a prerequisite documented in README |
| EPOCH_DURATION keeper sync issues on testnet (chain congestion) | Medium | Low | Keeper uses block.timestamp range with buffer; epoch can be settled permissionlessly by anyone |
| U2/U3 blocked by missing Stripe keys | Low | Medium | Graceful degradation — "Pay with Card" button hidden if `STRIPE_SECRET_KEY` not set; existing ZENT flow still works |
| WalletConnect Project ID exposed in frontend | Low | Medium | Use `NEXT_PUBLIC_` prefix per Next.js convention; this is a public key, not a secret |
| Supabase RLS policies prevent keeper from writing | Medium | High | Test RLS policies after migration; keeper uses service_role key with full table permissions |
| Front-running on provider signal submission | Low | Medium | Nonce mechanism in SignalRegistry prevents replay; front-running existing signals is mitigated by short signal expiry windows |

---

## Dependencies / Prerequisites

- `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID` must be obtained from cloud.walletconnect.com before U3
- `STRIPE_SECRET_KEY` and `STRIPE_WEBHOOK_SECRET` must be obtained from Stripe dashboard before U2
- `SCORING_ORACLE_PRIVATE_KEY` must be a funded account on HyperEVM testnet before U8
- All Supabase migrations (U9) must be applied before U2, U4, U5, U7, U8
- U1 (self-audit) should be started first so findings feed into U6 (whitepaper)

---

## Phased Delivery

### Phase 1 — Foundation (U9, then U1 + U3 in parallel)
U9 (Supabase schema) must run first — all other units depend on it.
U1 (self-audit) and U3 (wallet UX) are independent and can run in parallel.

### Phase 2 — Revenue & Trust (U2, U4, U8)
U2 (Stripe), U4 (leaderboard), and U8 (keeper) are largely independent but all require U9.
These three can run in parallel.

### Phase 3 — Analytics & Provider Infrastructure (U5, U7)
Both require U8 keeper to be running to generate real data.
U7 (provider portal) and U5 (analytics) can run in parallel.

### Phase 4 — Documentation (U6, U10)
U6 (whitepaper) requires U1 findings.
U10 (regulatory memo) is independent and can run in parallel with everything.

---

## Documentation / Operational Notes

- Keeper script requires a always-on server (VPS or cloud function) with cron access
- Stripe webhook requires HTTPS endpoint — use ngrok for local testing
- Supabase service_role key must be stored in keeper's `.env` — never committed to git
- `SCORING_ORACLE_PRIVATE_KEY` must be a dedicated account — not the deployer key
- After U8 is live, monitor `EpochScoring.accuracyCache` size to detect keeper failures
- All new Supabase tables need RLS policies reviewed before production

---

## Sources & References

- Smart contracts: `contracts/src/signals/SignalRegistry.sol`, `contracts/src/signals/EpochScoring.sol`, `contracts/src/signals/SubscriptionVault.sol`, `contracts/src/staking/ZENTStaking.sol`
- Frontend: `frontend/components/WalletSelector.tsx`, `frontend/app/subscribe/page.tsx`, `frontend/app/markets/page.tsx`
- Supabase schema: `supabase/migrations/2026_04_28_001_multi_asset_signal_network.sql`
- wagmi v2 WalletConnectConnector: https://wagmi.sh/core/api/connectors/walletConnect
- Stripe Checkout: https://stripe.com/docs/payments/checkout
- OWASP Smart Contract Top 10: https://owasp.org/www-project-smart-contract-top-10/
- Numerai Economic Model: https://numer.ai/whitepaper
