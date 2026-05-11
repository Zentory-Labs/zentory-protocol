# ZENTORY Strategy

*The single source of truth for what ZENTORY is building, for whom, and how we know we are winning. Maintained by ZENTORY Labs. Last updated: May 2026.*

This document is structured to be read in 5 minutes by an investor, a contributor, a rater, or an ecosystem partner. It is the upstream input to [`README.md`](README.md), [`COMPETITORS.md`](COMPETITORS.md), the whitepaper ([`docs/whitepaper.md`](docs/whitepaper.md)), and the marketing site copy at [zentorylabs.com](https://zentorylabs.com).

---

## 1. Target problem

**Crypto's signal market is broken, and DeFi vaults can't honestly say whether they're beating the asset they hold.**

Three observable facts:

1. **Paid signal groups are a ~$2.4B/year subscription market with no verifiable record.** Track records are screenshots; bad trades disappear. There is no canonical, signer-bound log that survives the deletion of a Telegram chat.
2. **Most DeFi vaults publish APY without an honest comparison to holding the asset.** A vault that pays 7% APR while the underlying gained 12% is destroying value, and the UI never says that.
3. **Mainstream copy-trading is custodial.** eToro, Bitget Copy, Bybit Copy, BingX Copy hold user assets to execute mirror trades. Post-FTX, this is a permanent compliance overhang and a withdrawal-freeze risk.

The structural opportunity: **HyperEVM ($2.8B TVL, 175+ teams) plus Hyperliquid execution depth** are the first L1 combination where a non-custodial, on-chain signal market can plausibly be settled at scale. The 2020 Yearn moment is repeating, with one extra dimension: this time the vault has a verifiable signal feed attached.

## 2. Users

We design for three concrete personas. Anything that doesn't serve at least one is out of scope.

### Persona A — "The depositor"
A DeFi-native crypto holder (1 BTC, 10 ETH, or equivalent across SOL / XRP / HYPE) who:
- Wants yield in the underlying asset, not in a governance token.
- Refuses to surrender custody.
- Has been burned at least once by an unverifiable APY claim.
- **What they get from ZENTORY:** an ERC-4626 vault they can deposit into and withdraw from at will, with on-chain Hold-vs-Ghost-vs-Actual attribution they can verify themselves.

### Persona B — "The quant"
A systematic researcher (independent, ex-hedge-fund, AI-augmented, or part of a small fund) who:
- Has a strategy they cannot prove without exposing it.
- Has no way to monetize signal accuracy without running a custodial product.
- Wants reputation that travels across protocols.
- **What they get from ZENTORY:** a signed EIP-712 signal log, a slashable ZENT stake that builds a reputation score, fee share from vault performance, and (via Subscription Vault) optional paid access.

### Persona C — "The HyperEVM ecosystem"
Hyperliquid market makers, HyperEVM dApp builders, treasury managers, and ecosystem funds who:
- Want native non-custodial yield products built **on** HyperEVM, not bridged.
- Need a credible "where do retail go for yield" answer for the ecosystem.
- **What they get from ZENTORY:** a flagship vault primitive they can integrate with, route liquidity to, or partner against without rebuilding the stack.

## 3. Approach

ZENTORY is built as **four primitives that only have value when stacked together.**

| Primitive | Contract / file | What it does |
|---|---|---|
| Alpha Vault (ERC-4626) | [`contracts/src/vaults/BaseVault.sol`](contracts/src/vaults/BaseVault.sol) | Holds underlying, mints share tokens, accrues fees, enforces circuit breaker |
| Mandate-bounded executor | [`contracts/src/keeper/StrategyExecutor.sol`](contracts/src/keeper/StrategyExecutor.sol) | EIP-712 verifies signal, enforces position/leverage limits, nonces |
| Signal registry + epoch scoring | [`contracts/src/signals/SignalRegistry.sol`](contracts/src/signals/SignalRegistry.sol), [`contracts/src/signals/EpochScoring.sol`](contracts/src/signals/EpochScoring.sol) | Canonical signed log of every signal + transparent epoch settlement |
| Reputation token | [`contracts/src/ZENT.sol`](contracts/src/ZENT.sol) + [`contracts/src/staking/ZENTStaking.sol`](contracts/src/staking/ZENTStaking.sol) | Stake to submit signals; slashable; veZENT governance; buyback-and-burn from vault fees |

The mechanism that makes the stack **mean** something is the **Ghost Portfolio**:

- **HOLD** = passive baseline (price * starting units).
- **GHOST** = simulated path of accepted signals at signal-stamped prices.
- **ACTUAL** = on-chain NAV including real slippage and fees.

Total alpha = ACTUAL − HOLD. Signal alpha = GHOST − HOLD. Execution alpha = ACTUAL − GHOST. Every number reconstructible from on-chain events. This is the **first attribution primitive of its kind** delivered as on-chain events plus an indexer, not a marketing dashboard.

We deliberately avoid:
- A discretionary "fund manager" role (defeats the trust model).
- Token emissions that subsidize TVL (creates mercenary capital, destroys the price signal of real revenue).
- Custody of user assets (the entire point is non-custodial).
- Cross-chain complexity before mainnet (single L1 first; multi-chain on the 2027 roadmap).

## 4. Key metrics

We will be judged by, in order:

| Tier | Metric | Why it matters | Target by Q4 2026 |
|---|---|---|---|
| North star | Cumulative on-chain alpha generated for depositors (in USD) | Real value created, not TVL theater | > $5M cumulative |
| Lead | Vault TVL (across zBTC / zETH / zSOL / zXRP / zHYPE) | Capacity of the alpha engine | $10M+ |
| Lead | Active signal submitters (with > 0 ZENT staked) | Health of the supply side | 50+ |
| Lead | Median signal accuracy per epoch (basis-point of price prediction) | Quality of the supply side | > 55% directional |
| Lag | ZENT fee-buyback volume (USD/month) | Revenue-driven deflation working | > $20k/month |
| Lag | Subscriptions sold (`SubscriptionVault`) | Demand-side monetization | 300+ active |
| Health | Time from signal submit → execution → settlement (median) | Operational quality | < 2 minutes |
| Health | Number of incidents (`docs/runbooks/incident-response.md`) | Production discipline | < 4 / quarter, none critical |

We explicitly do **not** optimize for: holder count, Twitter followers, raw TVL without alpha, or token price. Those follow the above when the above are honest.

## 5. Tracks of work

Active tracks (each owned, each instrumented):

### Track 1 — Vaults & execution
*Goal:* zBTC, zETH, zSOL, zXRP, zHYPE live on HyperEVM testnet with real Hyperliquid fills.
*Status:* live on testnet (chain id 998). Indexed via [`engine/scripts/index_strategy_executor_events.py`](engine/scripts/index_strategy_executor_events.py) and [`engine/scripts/poll_hyperliquid_fills.py`](engine/scripts/poll_hyperliquid_fills.py).
*Next:* mainnet audit (G1–G10 verification plan), fee evaluator stress tests.
*Owned by:* protocol team.

### Track 2 — Signal Arena
*Goal:* on-chain signal registry, EpochScoring, conviction leaderboard, SubscriptionVault tiers.
*Status:* contracts deployed on testnet; TypeScript keeper running ([`contracts/keeper/`](contracts/keeper)).
*Next:* Ghost Portfolio dashboard in the dApp, Conviction Score v1, Auto-Follow.
*Owned by:* protocol team + dApp team.

### Track 3 — Quant supply
*Goal:* 50+ independent quants submitting signals against testnet vaults; published accuracy leaderboard.
*Status:* engine ([`engine/`](engine)) provides a signing helper and a strategy template; Lumibot integration in progress.
*Next:* Volatility Brackets tournaments (per pitch deck slide 12).
*Owned by:* research + comms.

### Track 4 — Token, treasury, governance
*Goal:* ZENT TGE conditions met (utility live, fee loop active), veZENT governance functional.
*Status:* ZENT + vesting + buyback contracts deployed; Timelock + Governor wired; treasury flow defined in whitepaper §6.4.
*Next:* on-chain governance dry run, audit, public docs.
*Owned by:* protocol + legal.

### Track 5 — Compliance & security
*Goal:* clean external audit, Immunefi bounty live, geo-blocking compliant with documented jurisdictions.
*Status:* internal pentest 2026-04-26; [`SECURITY.md`](SECURITY.md) published; geo logic in [`frontend/proxy.ts`](frontend/proxy.ts).
*Next:* external audit firm engagement, Immunefi go-live.
*Owned by:* security.

### Track 6 — Public surface
*Goal:* discoverable, scrapable, verifiable public presence (this is the rating-platform delta).
*Status:* marketing site live (zentorylabs.com), dApp live, X handle dormant.
*Next:* public README + STRATEGY + COMPETITORS + TEAM, JSON-LD, social cold-start, founder verification.
*Owned by:* comms.

## 6. Non-goals (explicit)

- We do not run a discretionary fund.
- We do not custody assets.
- We are not a launchpad / IDO / fundraising platform.
- We do not promise yield from holding ZENT.
- We do not subsidize TVL with token emissions.
- We do not build on chains where we do not have execution-venue depth (HyperEVM + Hyperliquid first; multi-chain is a 2027 question, not a 2026 question).

## 7. Operating principles

1. **On-chain or it didn't happen.** Every claim in the protocol has an on-chain artifact backing it.
2. **Mandate before discretion.** A signer can only do what the contract permits; we never patch trust by trusting a person.
3. **Always show HOLD, GHOST, and ACTUAL — including when alpha is negative.** Hold is the honest baseline; Ghost is the signal-attributable path; Actual is real NAV. We always publish all three so users see the truth about their alpha, including underperformance.
4. **Revenue before subsidy.** Real fee revenue drives the buyback; we never use emissions to fake adoption.
5. **One chain, deeply.** HyperEVM until the protocol is durable; resist multi-chain temptation that fragments liquidity and audits.

## 8. Risks we are managing

| Risk | Mitigation |
|---|---|
| Smart-contract bug | Foundry test/fuzz/invariants in CI; Slither in CI; external audit gate (G1–G10) before mainnet |
| Signer key compromise | EIP-712 nonces + expiry; `GUARDIAN_ROLE` circuit breaker; rotatable authorized signer; staking slash |
| Quant adverse selection (poor signals) | ZENT stake bond; epoch-level slash; minimum stake; conviction-weighted execution |
| Regulatory (security classification of ZENT) | Utility-first design; buyback memo in [`docs/BUYBACK_DESIGN.md`](docs/BUYBACK_DESIGN.md); geo-blocking; no promised yield on token |
| HyperEVM concentration risk | Single L1 by design until durable; multi-chain on 2027 roadmap |
| Custody / oracle risk in execution | HyperCore is the execution venue, not custodian; vault assets remain in vault contract; oracle feeds documented |

## 9. How we ask to be evaluated

- Read this document.
- Read [`docs/whitepaper.md`](docs/whitepaper.md) v2 for the full mechanism.
- Inspect [`contracts/src/`](contracts/src) for the on-chain implementation.
- Check CI green at [`.github/workflows/ci.yml`](.github/workflows/ci.yml).
- Compare us to the cells in [`COMPETITORS.md`](COMPETITORS.md).
- Watch the testnet at [app.zentorylabs.com](https://app.zentorylabs.com).

If after that you cannot find what is novel, where in the ecosystem we sit, or how we differentiate, please open an issue or email `contact@zentorylabs.io` — that's a documentation bug on our side.
