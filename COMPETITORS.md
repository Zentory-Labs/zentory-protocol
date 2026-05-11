# Competitive Landscape

*How ZENTORY positions against every adjacent category. Last updated: May 2026.*

This document exists to remove ambiguity about whether ZENTORY is "another vault" or "another copy-trading product." It is neither, because no existing competitor combines vaults + signed signals + on-chain reputation + non-custodial execution + buyback-and-burn on HyperEVM. The table at the bottom proves this cell-by-cell.

For the abstracted mechanism, see [`STRATEGY.md`](STRATEGY.md) and [`docs/whitepaper.md`](docs/whitepaper.md). For Solidity-level proof, see [`contracts/src/`](contracts/src).

---

## Categories we map against

We track 8 adjacent product categories. Each has competitors that solve part of what ZENTORY solves. None solve the full stack.

### A. Centralized paid signal services

**Examples:** WhaleClub, Cornix, Crypto Quality Signals, "VIP" Telegram groups, signal Discord servers, paid Twitter newsletters.

**What they do well:** mass distribution, low friction, real research talent on the supply side.

**What they fail at:**
- Track records are screenshots. Bad signals are silently deleted.
- No cryptographic signer identity per call.
- No native execution venue; the user has to trade manually on their own CEX.
- Subscription is custodial of *attention*, not of *capital*, but performance accountability rounds to zero.

**Where ZENTORY beats them:** every signal is signed (EIP-712), time-stamped, and scored on-chain. A bad quant can be slashed, not just unfollowed.

### B. Centralized copy-trading

**Examples:** eToro, Bitget Copy, Bybit Copy, BingX Copy, OKX Copy, Binance Lead Trading.

**What they do well:** UX, scale, integration with their own spot/perp venues, "social" follower mechanics.

**What they fail at:**
- Custodial. Users surrender keys to the exchange.
- Opaque order routing; withdrawal freeze risk.
- Reputation is platform-local; it doesn't travel.
- Compliance / KYC overhead skews to retail-only markets.

**Where ZENTORY beats them:** non-custodial by construction. Vault assets sit in the ERC-4626 contract; `StrategyExecutor` cannot exceed mandate; user withdraws on demand.

### C. DeFi-native copy / social trading

**Examples:** dHEDGE, Enzyme (formerly Melon), Set Protocol (legacy), Reserve, more recently Hyperliquid Vaults (native).

**What they do well:** non-custodial; on-chain accounting.

**What they fail at:**
- Trust model is "trust the fund manager," not "trust a signed and slashable signal."
- No standardized signal-feed primitive across managers.
- No reputation token with slashable stake; reputation is informal.
- Limited or no Hyperliquid-native execution adapter.

**Where ZENTORY beats them:** the manager is replaced by an EIP-712 signer governed by the vault. Bad signers get slashed by `ModelBonding` / `ZENTStaking`, not just unsubscribed.

Hyperliquid's own native vaults are the closest single-feature analogue (non-custodial, on the same venue), but they have no separate signal-registry layer and no cross-vault reputation token.

### D. Generic yield vault aggregators

**Examples:** Yearn (v3), Beefy Finance, Sommelier, Idle Finance, Convex.

**What they do well:** automation, gas-efficient strategies, well-audited at this point.

**What they fail at:**
- "APY in a box." No standardized comparison to passively holding the underlying.
- No quant identity behind strategies — they are protocol-team-authored or community-contributed code.
- No signal-feed primitive.

**Where ZENTORY beats them:** Ghost Portfolio attribution. Yearn cannot tell you what its alpha *would have been* if it had taken a different signal path; ZENTORY can, by construction.

These are not strict competitors — ZENTORY could integrate them as underlying yield sources on the asset side. The differentiation is at the *signal* and *attribution* layer.

### E. Quant reputation / tournament protocols

**Examples:** Numerai (and Numerai Signals), CrunchDAO, Rocket Pool prediction tournaments, OpenQuant.

**What they do well:** crowdsourced quant supply; staking-with-skin-in-the-game; reputation as a primitive.

**What they fail at:**
- Numerai is hedge-fund-opaque: stakers do not deposit capital into the strategy they predicted, they predict for the central fund.
- No on-chain consumer-facing vault for retail to deposit into.
- No execution venue. The signal goes to the central fund, not to your wallet.
- Reputation is intra-protocol; it doesn't compose with DeFi vaults.

**Where ZENTORY beats them:** the signal **directly executes** against a vault that retail deposits into. Quant reputation translates into real fee revenue, not just NMR/CRUNCH payouts. Reputation is composable with the rest of HyperEVM DeFi.

### F. Prediction / outcome markets

**Examples:** Polymarket, Augur (legacy), Limitless, Kalshi (regulated, off-chain settlement).

**What they do well:** discrete-outcome prediction; transparent settlement; deep liquidity in some events.

**What they fail at:**
- Bets on outcomes, not continuous trading signals.
- No vault primitive for continuous yield.
- No reputation token tied to multi-asset signal accuracy over time.

**Where ZENTORY beats them:** wrong category for the depositor persona. A polymarket position is a one-shot directional bet; a ZENTORY vault deposit is continuous exposure plus continuous signal-driven alpha.

### G. Automated quant funds (Web2 wrappers)

**Examples:** Stoic AI, 3Commas, Pionex, Mudrex, Shrimpy.

**What they do well:** automation, accessible UI, low-end-user knowledge required.

**What they fail at:**
- Custodial via API keys or wallet sharing.
- Closed-source strategies; no signed signal trail.
- Centralized failure modes.
- Geographic restrictions vary widely.

**Where ZENTORY beats them:** wallet-native, signed, slashable. No API key sharing, no opaque strategy.

### H. Index / structured product issuers

**Examples:** Index Coop, Tokemak, Ribbon (now Aevo), Friktion (legacy).

**What they do well:** packaged exposure; tokenized products; transparent rebalance rules.

**What they fail at:**
- Rule-based, not signal-based. Cannot react to short-horizon alpha.
- No quant-identity layer; the "manager" is the protocol.
- No on-chain attribution beyond simple NAV.

**Where ZENTORY beats them:** ZENTORY is structurally a *managed* vault where the manager is replaced by a market of signed signals. Different design point.

---

## The single comparison table

Each row is a feature the rater (or an investor) would care about. Each column is a competitor. We are the only column that fills every row.

| Capability | ZENTORY | Numerai | Yearn / Beefy | eToro / Bitget Copy | dHEDGE / Enzyme | Hyperliquid Native Vault | Polymarket | Telegram Signal Groups |
|---|---|---|---|---|---|---|---|---|
| Non-custodial (no exchange custody; user-initiated withdrawal from vault contract) | Yes | n/a (no deposit) | Yes | **No** | Yes | Yes | Yes | n/a |
| On-chain signal registry (EIP-712) | **Yes** | No | No | No | No | No | No | No |
| Per-signal accuracy settled on-chain | **Yes** | Internal only | No | No | No | No | Outcome only | No |
| Vault attribution spec + contracts (Hold / Ghost / Actual events) | **Yes** | No | No | No | No | No | No | No |
| End-user verifiable attribution dashboard (Ghost UI shipped) | **Partial** (contracts + indexer live; Ghost scoring UI in flight) | Partial | Partial | No (paywall) | Yes | Yes | Yes (outcomes) | No |
| Reputation token w/ slash + stake | **Yes** (ZENT) | Yes (NMR) | No | No | No (manager fee only) | No | Partial | No |
| Fixed-supply utility token (no inflation) | **Yes** | No | n/a | n/a | n/a | n/a | n/a | n/a |
| Buyback + burn from real protocol revenue | **Yes** (50% of fees) | No | No | No | No | No | No | No |
| HyperEVM native | **Yes** | No | No | No | No | Yes | No | No |
| Hyperliquid execution adapter | **Yes** | No | No | n/a | Limited | Native | No | No |
| Mandate-bounded executor (position/leverage caps enforced in Solidity) | **Yes** | n/a | n/a | No (CEX) | Manager-bounded | Limited | n/a | n/a |
| Per-vault circuit breaker | **Yes** | n/a | Yes | Platform-level | Manager-level | Yes | n/a | n/a |
| Open-source contracts | **Yes** (this repo) | Partial | Yes | No | Yes | Partial | Yes | No |

**Reading the table:** the diagonal of "Yes" columns shows that every existing player solves one or two of these problems. Only ZENTORY targets the full stack as the product, on HyperEVM, with a real execution venue attached.

**Note on `Yes` vs `Partial`.** The capability matrix reflects the **target architecture at mainnet (Q4 2026)**. Cells marked `Partial` reflect work that is shipping in flight (contracts and indexer present today; consumer-facing surface still landing). See the [`Status`](README.md#status) section of the README for per-feature readiness.

---

## Honest things competitors do better today

We are not pretending parity exists where it doesn't. As of May 2026:

- **eToro / Bitget Copy** have orders of magnitude more users than we will at mainnet launch. We will not match retail-friendliness for at least a year.
- **Yearn / Beefy** have audit and operational track record we have not earned yet.
- **Numerai** has a more mature quant tournament economy than we will have at launch.
- **Hyperliquid native vaults** have a UX-and-distribution edge we will need to earn against.
- **dHEDGE / Enzyme** have years of compliance/legal scaffolding on the fund-manager model.

ZENTORY's bet is that the **mechanism** is structurally better and that the **HyperEVM moment** is the right window. The competitors above will be slower to retrofit non-custodial signed signals than we will be to earn distribution and track record.

---

## Bottom-line positioning

> **ZENTORY is the first protocol where a depositor's yield, a quant's reputation, a token's value capture, and an attribution-grade alpha measurement all share the same on-chain primitives — on a chain where the execution venue is deep enough for it to matter.**

If a project lays the same claim later, we expect them to be either (a) building on HyperEVM after watching us prove the model, or (b) trying to bolt non-custodial signal feeds onto a custodial copy-trading product, which is structurally hard.
