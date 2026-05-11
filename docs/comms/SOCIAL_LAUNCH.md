# Social Launch Playbook — @ZENTORYLabs

*Owner: Shaman (ops/PR). Reviewers: Edge, founders. Last updated: May 2026.*

The rating report scored Social Presence **20/100** with explicit notes:

- "There are no tweets posted by the account."
- "The account has a very small following (10 followers) and no tweet activity."

This is fixable in days, not months, but only with a deterministic launch sequence. This document is the sequence.

Contents:

1. [C1 — Verify the handle](#c1--verify-the-handle)
2. [C2 — Pinned "What is ZENTORY" thread](#c2--pinned-what-is-zentory-thread)
3. [C3 — Cornerstone post drop (6 posts)](#c3--cornerstone-post-drop-6-posts)
4. [C4 — Engagement playbook and cadence](#c4--engagement-playbook-and-cadence)

---

## C1 — Verify the handle

The rating platform that issued the 56/100 score lists `@zentorylabs` as **Unverified**. Verification means linking the X account to the project record on the rating platform so the platform's scraper trusts the content history.

### Step-by-step

1. **Log into** the rating platform (whoever set up the project record originally).
2. **Open** the project page for `edgeza/ZentoryToken`.
3. **Click** "Verify project handle" (label varies by platform; sometimes "Connect Twitter/X").
4. **Authorize** via X OAuth, OR copy the verification code the platform issues and tweet it from `@ZENTORYLabs`.
5. **Update X bio** to include `zentorylabs.com` and `github.com/edgeza/ZentoryToken`.
6. **Update X header / banner image** to the same artwork as the GitHub social preview (`STEP 5` of [`GITHUB_SETTINGS.md`](../../GITHUB_SETTINGS.md)).
7. **Update pinned tweet** to the C2 thread below as soon as it is posted.

### X account hygiene checklist

| Field | Target value |
|---|---|
| Handle | `@ZENTORYLabs` |
| Display name | `ZENTORY` (or `ZENTORY \| Signal Arena on HyperEVM`) |
| Bio | `The Signal Arena on HyperEVM. Non-custodial Alpha Vaults + EIP-712 signed signals + Ghost Portfolio attribution. zentorylabs.com` |
| Location | Where the team is based (or `On-chain`) |
| Website | `https://zentorylabs.com` |
| Avatar | ZENTORY mark on dark background (use `zentory_logo_dark.png` cropped square) |
| Header | 1500x500, same theme as GitHub social preview |
| Pinned tweet | C2 thread (below) |

Once verification is confirmed, complete [`D3`](#d3) (founder verification) before triggering re-rate.

---

## C2 — Pinned "What is ZENTORY" thread

Copy-paste ready. Post as a single thread; pin the first tweet. Each tweet is under 280 characters.

> **Note on links:** X de-prioritizes posts with external links, so link-only tweets go later in the thread and standalone external links are replaced with `(link in reply)` where possible. The final reply contains all links.

### Tweet 1 of 10 — hook (pin this one)

```
What if every quant signal in crypto was on-chain, signed, and slashable?

What if a vault could prove exactly how much alpha each signal contributed?

What if copy-trading didn't require you to surrender custody?

That's ZENTORY. The Signal Arena on HyperEVM. 🧵
```

### Tweet 2 of 10 — problem 1

```
The crypto signal market is ~$2.4B/yr in Telegram VIP subscriptions.

Track records? Screenshots.
Bad trades? Quietly deleted.
Signer identity? Vibes.

You're paying $200/mo for an unverifiable claim of alpha. That's the state of the art today.
```

### Tweet 3 of 10 — problem 2

```
DeFi vaults publish APY without an honest comparison to holding the asset.

A vault that pays 7% APR while ETH gained 12%? Destroying value.

The UI never tells you. No vault has a standard primitive for separating beta, signal alpha, and execution slippage.

Until now.
```

### Tweet 4 of 10 — problem 3

```
Mainstream copy-trading (eToro, Bitget Copy, Bybit Copy, BingX Copy) is custodial.

Post-FTX, that's a permanent compliance and withdrawal-freeze risk.

The non-custodial alternative? It hasn't existed, because no chain had the execution depth for it. Until HyperEVM.
```

### Tweet 5 of 10 — solution: vaults

```
ZENTORY Alpha Vaults are ERC-4626 vaults on HyperEVM.

Deposit BTC, ETH, SOL, XRP, or HYPE. Earn yield in the underlying — not in our token.

Withdrawals are on-demand share redemptions. No lockup beyond your own decision. The vault is the contract.
```

### Tweet 6 of 10 — solution: signal arena

```
Quants stake ZENT and submit EIP-712 signed signals against vaults.

Every signal is time-stamped, signer-bound, and on-chain forever.

Epoch settlement scores accuracy. Bad signers get slashed. Good signers earn fees + reputation that travels.

Telegram screenshots? Obsolete.
```

### Tweet 7 of 10 — Ghost Portfolio (the heart of it)

```
The mechanism no one else has: the Ghost Portfolio.

For every vault, we track three NAVs in parallel:

— HOLD: passive baseline
— GHOST: signal path at signed prices
— ACTUAL: real on-chain NAV

ACTUAL − HOLD = total alpha
GHOST − HOLD = signal alpha
ACTUAL − GHOST = execution alpha

Reconstructible from chain events. No dashboard to trust.
```

### Tweet 8 of 10 — token

```
ZENT is utility + governance. 1,000,000,000 fixed supply. No inflation.

Used for:
— Signal staking (slashable)
— Conviction weighting
— Access tiers
— veZENT governance
— Fee payment

50% of vault performance fees → buyback and burn ZENT.

No yield on holding. No equity. Not a security.
```

### Tweet 9 of 10 — why HyperEVM, why now

```
Why HyperEVM:
— $2.8B TVL, 175+ teams, fastest-growing EVM chain
— Hyperliquid: one of the deepest on-chain perp venues by volume
— No incumbent quant-reputation layer yet

This is the 2020 Yearn moment with one extra dimension: the vault now has a verifiable signal feed attached.
```

### Tweet 10 of 10 — links and CTA

```
Verify everything we just claimed:

→ Site: zentorylabs.com
→ Why ZENTORY (vs Numerai, Yearn, eToro Copy, dHEDGE): zentorylabs.com/why
→ Whitepaper: zentorylabs.com/whitepaper
→ dApp (testnet): app.zentorylabs.com
→ Contracts: github.com/edgeza/ZentoryToken

The Signal Arena is coming. Be early.
```

---

## C3 — Cornerstone post drop (6 posts)

One per week for six weeks, after the C2 thread is pinned. Each post is a self-contained mini-thread (3–8 tweets) on one substantive topic.

The point is **density** of substantive crypto-quant content. Vague "we're building something exciting" tweets score zero on the rater's content-relevance axis.

### Post 1 — Ghost Portfolio explained (Week 1)

**Format:** 6-tweet thread + screenshot of dApp Ghost Portfolio panel (when live; placeholder mockup otherwise).
**Hook:**

```
Why does every DeFi vault tell you APY but not whether they beat holding the asset?

Because attribution is hard.

We made it a primitive. Meet the Ghost Portfolio. 🧵
```

**Content beats:**

1. Definition of HOLD / GHOST / ACTUAL.
2. Why the GAP between them is the only number that matters.
3. Worked example with numbers (use the +18.7% GHOST vs +2.3% HOLD vs +23.1% ACTUAL example from the whitepaper).
4. Why this is impossible to fake — every input is on-chain.
5. How a depositor uses it (deposit, watch GHOST diverge from HOLD, that's signal alpha you're paying for).
6. CTA: link to `zentorylabs.com/why#defi-copy` or whitepaper §4.3 (Ghost Portfolio) and §8 (attribution).

### Post 2 — ZENT utility (not a security) (Week 2)

**Format:** 5-tweet thread.
**Hook:**

```
ZENT is a fixed-supply utility token on HyperEVM.

1,000,000,000 supply. No inflation. No yield from holding.

Five distinct utilities. One fee-driven deflationary loop. Here's how it works. 🧵
```

**Content beats:**

1. The five utilities (signal staking, conviction, access, veZENT, fee payment) with one line each.
2. How vault performance fees route through `FeeDistributor` → 50% buyback / 25% treasury / 15% insurance / 10% ops.
3. Why "buyback" is supply management, not yield distribution.
4. Why fixed supply matters: every real-revenue dollar is deflationary, not dilutive.
5. CTA: link to `zentorylabs.com/tokenomics` and whitepaper §6.

### Post 3 — HyperEVM ecosystem map (Week 3)

**Format:** 4-tweet thread + a single image (ecosystem map graphic).
**Hook:**

```
HyperEVM is the fastest-growing EVM chain right now. $2.8B TVL. 175+ teams.

Most people still don't have a mental model of what's there. Here's the map. 🧵
```

**Content beats:**

1. Hyperliquid execution layer.
2. Major HyperEVM protocols (lending, perps, vaults, stables) — name 6–8 and tag them.
3. The gap: no native quant-reputation layer. That's the ZENTORY slot.
4. CTA: follow @ZENTORYLabs.

### Post 4 — EIP-712 signal flow (Week 4)

**Format:** 5-tweet thread + a code-style image of a signed signal payload.
**Hook:**

```
Every ZENTORY signal is signed with EIP-712 before it ever touches a vault.

Why? Because "trust the screenshot" isn't a security model.

Here's exactly what gets signed and why each field is non-negotiable. 🧵
```

**Content beats:**

1. The signal payload structure (vault, direction, size, price, nonce, expiry).
2. Why `nonce` (replay defense).
3. Why `expiry` (no stale signals after market moves).
4. Why mandate-bounded execution can't be exceeded by the signer.
5. CTA: link to `StrategyExecutor.sol`.

### Post 5 — Fee → buyback flow (Week 5)

**Format:** 4-tweet thread + a flow diagram.
**Hook:**

```
50% of every ZENTORY vault performance fee buys ZENT and burns it.

This is supply management, not a yield distribution. Here's the difference and why it matters legally + economically. 🧵
```

**Content beats:**

1. The flow: vault yield → 15% performance fee → `FeeDistributor` → 50% buyback.
2. Why "buyback" ≠ "share buyback" in the equity sense (no claim on revenue per token).
3. Why this avoids the Howey test on the utility design.
4. CTA: link to `docs/BUYBACK_DESIGN.md`.

### Post 6 — Roadmap (Week 6)

**Format:** 5-tweet thread + timeline image.
**Hook:**

```
ZENTORY roadmap to mainnet. Not vibes. Dates. Audits. Gates.

🧵
```

**Content beats:**

1. April 2026: testnet live (already shipped).
2. May 2026: Hyperliquid fill pipeline indexed.
3. Q3 2026: Ghost Portfolio public dashboard, Conviction Score v1, leaderboard.
4. Q4 2026: External audit (G1–G10 gates), Auto-Follow, Volatility Brackets S1, mainnet.
5. 2027: multi-chain, equity signals, governance launch.

---

## C4 — Engagement playbook and cadence

The rater scored 20 on Engagement Quality and Audience Authenticity in addition to Content Relevance. Posting alone is half the job; the other half is engagement.

### Posting cadence

| Day | What | Owner |
|---|---|---|
| Mon | Cornerstone thread (C3) | Shaman |
| Tue | Reply / quote-tweet on a HyperEVM ecosystem story | Shaman |
| Wed | One technical detail post (contract, fuzz finding, design insight) | Edge |
| Thu | One ecosystem amplification (mention a partner, a research piece) | Shaman |
| Fri | One depositor-facing explainer or "how to use the testnet" post | Shaman |
| Sat | Optional: meme / culture post | anyone |
| Sun | Off |

Minimum: **3 posts per week**, average **5**. Below this floor, the rater's content-relevance metric will not recover from 20.

### Engagement floor (every weekday)

- Reply to **5 HyperEVM-ecosystem accounts** (Hyperliquid team, prominent HyperEVM dApps, key researchers). Substantive replies only — no "great post!" replies.
- Quote-tweet **1 ecosystem news item** with a 1–2 sentence ZENTORY take.
- Follow **5 high-signal accounts/week** in HyperEVM, DeFi quant, copy-trading-skeptic narrative.

### Targets to follow first (day 1)

- @HyperliquidX, @hyperliquid_evm (and the developer accounts behind them)
- Major HyperEVM dApps (whoever the current TVL leaders are at posting time)
- @numerai, @dHEDGEorg, @enzymefinance — competitor accounts (good for context replies)
- 10–15 well-known DeFi-quant accounts (these vary by month)
- A few crypto journalists who cover protocol launches

### What NOT to do

- No "gm" / "wagmi" / engagement-bait threads. The rater downweights these and they devalue the brand.
- No emojis-as-substance posts ("🚀🚀🚀").
- No paid follower campaigns. Audience-authenticity score punishes this.
- No replies to scams or low-effort accounts (they'll farm us for visibility).
- No engagement with anonymous shillers offering "partnership."

### Measurement

Track weekly:

- Follower delta (target: +50/week for the first month, +200/week by month 3).
- Impressions per post (target: 5x growth over the first 90 days).
- Reply rate from ecosystem accounts (target: 2 substantive replies per week from accounts with >5k followers).
- Profile clicks → site sessions (Vercel Analytics on `zentorylabs.com`).

Report these weekly in `#comms` channel (or equivalent). If a metric flatlines for two weeks, change the content mix.

---

## When to trigger re-rate

The plan is to wait **3 weeks** after C2 + first three C3 posts ship before clicking "Re-rate" on the rating platform. Reasons:

- Content history depth matters more than count. 0 → 15 substantive posts is a step function.
- Follower count will lag by 2–4 weeks regardless of posting effort.
- The Founders score (D3) and Repository verification (`GITHUB_SETTINGS.md` STEP 10) should land first; they are binary flips that lift the score immediately.

Expected Social score after this playbook executes for 3 weeks: **40–60** (up from 20). Hitting **70+** typically requires 6+ weeks of consistent cadence.
