# Decision #68 — Signal accuracy scoring methodology

*Status: **ACCEPTED** (decided 2026-06-12; standing veto: Edge, Head of Algo & Strategy).*
*Implemented in `contracts/src/signals/EpochScoring.sol::_calculateAccuracy`; tests in `contracts/test/signals/EpochScoring.captureAccuracy.t.sol` and the updated `EpochScoringSnapshotOrder.t.sol`.*

## Problem

Providers submit a **long-only conviction** (`direction` ∈ 0..10000, i.e. a target
exposure — `target_frac × 1e4`), but the original `_calculateAccuracy(actual, signal)`
rewarded *numeric closeness* between that conviction and the epoch's realized price
move in **basis points**. The two scales are incommensurable: a realistic 4-hour move
is ±tens-to-hundreds of bps while conviction is thousands, so accuracy was ~0 for
every provider in every epoch regardless of skill. Accuracy was structurally
unearnable — the on-chain reputation layer could never light up (the live leaderboard
shows 0.0% for a provider with 44 submissions for exactly this reason).

## Decision: exposure-weighted directional capture

```
captureBps = conviction × actualMoveBps / 10000      // what a vault following the
                                                     // signal actually earned vs flat
accuracy   = 5000 + clamp(captureBps × 10, ±5000)    // mapped onto the 0..10000 scale
```

- **5000 = neutral.** Flat (conviction 0) or a zero-move epoch scores exactly 5000.
  This aligns 1:1 with the payout curve's documented break-even
  (`PayoutCurve.t.sol`: accuracy 5000 pays exactly 0; below = slash, above = reward) —
  no payout-side change needed.
- Full conviction on a +100 bps epoch → 6000; on a −100 bps epoch → 4000.
- Saturates at ±500 bps captured per epoch (a >5% four-hour move captured at full
  conviction is max/min score either way).
- Defensive clamps on conviction (0..10000) so historical out-of-range data can
  never revert settlement.

## Why this over the alternatives

1. **It scores what the product pays for.** A target-weight vault following a
   signal earns `conviction × move` — the score *is* the provider's economic value
   added vs sitting flat. It is also exactly the GHOST−HOLD attribution the dApp
   already renders, so one mental model spans vaults, leaderboard, and Arena.
2. **Predicted-bps re-encoding (rejected):** engine-only change, but it forces
   trend strategies — which forecast *exposure*, not move magnitude — to fake a
   number they don't produce. Dishonest fit, and it repurposes the `direction`
   field's public semantics.
3. **Correlation/Numerai-style (rejected for v1):** needs per-provider history
   windows and is impractical to compute on-chain per epoch; revisit off-chain
   scoring with on-chain settlement post-mainnet if the provider population grows.
4. **Incentive properties:** monotone in captured move; flat is never punished
   (no-call = no score movement, matching "in cash is a position" strategy
   semantics); over-conviction in the wrong direction is punished proportionally.
   With long-only conviction there is no way to profit from inverting a bad
   signal; signed conviction (shorts) is a v2 registry change, the formula
   already handles negative capture.

## Rollout

- Code lands on `main` now → included in the refreshed audit freeze (auditors review
  the final formula, not the dead one).
- **Live testnet stack (EpochScoring 0x659569A6…) keeps the old bytecode** until the
  next `RedeploySignalStack.s.sol` broadcast (Edge, deployer key). The dApp's
  "accuracy scoring not yet settled" banners stay honest until then and auto-clear
  on the first settled epoch with real accuracy.
- Mainnet deploys this formula natively.
- UI note: 5000 (=50%) is the neutral baseline, not a coin-flip; grade bands in the
  leaderboard should read 50% as "no value added yet", not "D".
