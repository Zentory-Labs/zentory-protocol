# TGE structure (M7)

Token generation event plan for ZENT mainnet launch. This is the working
document — exact percentages may shift ±2% based on legal opinion +
audit timing, but the structure below is the published intent.

Last updated 2026-05-26.

---

## Supply

- **Total:** 1,000,000,000 ZENT (1B fixed)
- **Decimals:** 18
- **No mint function.** Supply is set at deploy. Cannot be inflated post-launch.
- **Contract:** `ZENT.sol` — see `contracts/src/ZENT.sol`
- **Testnet address:** `0x271cd48c1297CacCD810c7B1BCD904f459df7117` (HyperEVM testnet)

---

## Distribution

| Bucket | % | Tokens | Vesting | Rationale |
|---|---|---|---|---|
| Team + founders | **18%** | 180M | 4-yr linear, 1-yr cliff | Standard founder economics. Cliff aligns team commitment with first audited mainnet year. |
| Treasury | **20%** | 200M | Time-locked, governance-released | Funds protocol development, audits, partnerships, market making. Governance-controlled releases prevent founder discretion. |
| Quant contributor rewards | **22%** | 220M | Emitted via EpochScoring | Continuously paid to quants based on signal accuracy. This is the protocol's primary alignment mechanism — the bigger the alpha demand, the bigger the contributor base. |
| LP rewards (vault depositors) | **10%** | 100M | 24-month linear emission | Bootstraps vault TVL. Higher in first 6 months, tapers. |
| ZENT/USDC liquidity (POL) | **8%** | 80M | Locked 12 months as Protocol-Owned Liquidity | $ZENT side of the seed pool on HyperSwap. Locked = credible price floor signal. |
| Testnet airdrop | **3%** | 30M | 25% at TGE, 75% linear over 6 months | Reward early dApp users + signal submitters + faucet users (M9). |
| Strategic round | **10%** | 100M | 18-mo linear, 6-mo cliff | Reserved for the strategic raise. Smaller cliff than team because strategics deliver value earlier. |
| Public DEX float | **5%** | 50M | Unlocked at TGE | Tradeable supply at launch. Concentrated on HyperSwap pool + a small Uniswap v3 bridged pool. |
| Bug bounty + insurance | **4%** | 40M | Multi-sig controlled, drawn down on payouts | Funds the Immunefi bounty pool + initial insurance fund seed. |
| **Total** | **100%** | **1,000M** | | |

Adjust as needed — these are the working numbers, not the committed ones.

---

## TGE float math

At T=0:
- 50M from public DEX float
- ~7.5M unlocked from testnet airdrop (25%)
- = **~57.5M tradeable** (~5.75% of supply)

This is deliberately low. Major DeFi launches with >15% float at TGE tend to bleed for 6+ months as early holders cycle out. A tight float + strong utility demand creates the price discovery we want.

---

## Vesting contract

`ZENTVesting.sol` (existing testnet address `0xf7c45f45768d790F388215A44d6E01f6f2568774`) handles linear and cliff vesting. Per-recipient schedules created at deploy time. Anyone can call `release()` on behalf of a recipient — the recipient still receives the tokens; only the gas is paid by the caller. This prevents recipients losing tokens if they're inactive.

For the airdrop, we use a separate `MerkleDistributor.sol` (to be deployed; not in repo yet) that gates claims on a Merkle proof.

---

## Liquidity bootstrapping (HyperSwap + Uniswap v3 bridged)

- **Primary:** HyperSwap on HyperEVM mainnet. Initial pool: $250k USDC + 80M ZENT (= $0.003125 starting price). $250k worth of POL locked in the pool for 12 months.
- **Secondary:** Uniswap v3 on Arbitrum or Base, bridged via lockbox. Smaller pool, ~$50k, for users who don't yet bridge to HyperEVM.
- **Concentrated liquidity:** v3-style ranges on HyperSwap. Initial range centered on starting price with 50% tighter band to bootstrap depth.
- **POL = no rug.** Locking the $ZENT side of the pool for 12 months means the team cannot pull liquidity. Auditors and Tier-1 LPs verify this.

---

## CEX listings

**Not at launch.** We deliberately skip Tier-1 CEX listings (Binance, Coinbase) — they require $1M+ fees and we'd rather direct that capital toward audit, security, and POL.

**Tier-2/3 CEXs at month 3–6 post-launch** if volume justifies it: Gate.io, MEXC, Bitget, BingX. Listing fees range $40–150k per exchange. We pick based on:
- Liquidity that listing brings (depth, fees, taker volume)
- Geographic reach (APAC vs EU vs US — we skip US-focused exchanges)
- Match to our user base (DeFi-native users vs retail)

---

## Buyback + burn cadence

Every Friday post-launch, the protocol:

1. Reads accumulated fees from each vault's `FeeDistributor`
2. Routes 50% of the perf fee share into `ZENTBuyback.sol`
3. `ZENTBuyback` swaps the underlying (USDC/WBTC/etc.) for ZENT on HyperSwap
4. Bought-back ZENT is sent to `0x000000000000000000000000000000000000dEaD`
5. Tx hash + amount tweeted publicly

This is a structural deflation tied to actual protocol revenue. The more vault NAV grows, the more ZENT gets burned. Predictable, transparent, no governance discretion.

---

## Vesting unlocks — visualized

```
Month 0:  TGE — 57.5M unlocked (5.75% of supply)
Month 6:  + airdrop tail (~22.5M) + LP rewards Q1 (~12.5M) + strategic cliff (16.7M)
Month 12: + team cliff release (45M) + strategic continuing (33.4M)
Month 24: + LP rewards complete (100M total) + strategic complete (100M total)
Month 48: + team complete (180M total)
```

By month 48, the entire team + strategic allocations are fully vested. Treasury, quant rewards, and bug-bounty buckets are governance-released and don't follow a strict schedule.

---

## What happens if the audit slips?

The TGE schedule is gated on audit + multisig migration. If the audit slips by N weeks:

- Mainnet contract deploy slips by N weeks
- TGE slips by N weeks (we will NOT launch the token before contracts are audited)
- Airdrop snapshot is taken closer to TGE (more participation captured)

Investors and contributors are aware of this gating. The schedule is intent, not commitment.

---

## What can governance change?

Once mainnet is live and governance is active (post-handoff):

- **Cannot:** total supply, vesting schedules already in flight, the 50/25/15/10 fee distribution split, the 4-hour epoch length without 30-day Timelock
- **Can:** epoch reward sizes (signal payouts), signal stake minimums per asset, treasury actions, parameter updates on existing vaults, deploy new vaults

The boundary between "cannot" and "can" is enforced in Solidity — there's no upgrade path on the protocol-critical primitives without full redeploy + migration.

---

## What I need from you to finalize this

1. Confirm or adjust the 18/20/22/10/8/3/10/5/4 percentage split. Round numbers are easier to defend in pitch decks than weird fractions.
2. Confirm the liquidity strategy (HyperSwap primary, Uniswap secondary, $250k initial pool)
3. Confirm the 12-month POL lock period (longer is safer but locks more capital)
4. Decide on the Tier-2/3 CEX listing budget cap (recommend $300k for first 12 months, max 2 exchanges)

---

*Tracked as task #99 (M7). Pre-audit document. Final numbers locked at audit kickoff.*
