# Decision Q6 — `MAX_SIGNAL_AGE` for `claimExpiredSignal` recovery path

*Status: **ACCEPTED** (decided 2026-08-21; standing veto: Edge, Head of Algo & Strategy).*
*Implemented in `contracts/src/signals/EpochScoring.sol::claimExpiredSignal`; tests in `contracts/test/signals/EpochScoringExpiredSignal.t.sol`.*

## Problem

Audit finding Q6 (HIGH, 2026-08-07) — `accuracyCache` defaults to 0 and 0 is the
MAXIMUM-slash input on the payout curve. A signal the scoring oracle never scored
is indistinguishable from a maximally-wrong one; a stalled oracle silently burns
every provider's stake on the next `applyPayout`.

The first half of the fix is mechanical: a sentinel (`accuracyScored[signalId] : bool`)
that `applyPayout` requires to be `true` before reading the cache. This reverts
the destructive direction with `SignalNotScored(signalId)`.

The second half needs a *tokenomics* decision: how long until a provider (or the
keeper on the provider's behalf) can declare a never-scored signal as released,
so the protocol can clear stale entries from the active queue without affecting
stake. The `claimExpiredSignal(signalId)` recovery path is the vehicle.

## Decision: `MAX_SIGNAL_AGE = 7 days`

- **Grace window:** 7 days from `SignalRegistry.submitSignal(submittedAt=block.timestamp)`
  before the recovery path becomes available.
- **What "recovery" does:** flips an off-chain-observable flag (`expiredClaimed[id] = true`),
  emits `ExpiredSignalClaimed(signalId, provider, ageSeconds)`, and *does not move any ZENT*.
  The signal was never paid out, so the provider's stake is unchanged either way —
  the flag exists purely so keepers / indexers can reconcile stale entries and so
  future `applyPayout` calls keep reverting with `SignalNotScored` (defense in
  depth — the recovery flag cannot be used to retroactively approve a payout).
- **Role gate:** `EPOCH_SETTLER` (the same role held by the keeper for `settleEpoch`
  and `applyPayout`). DEFAULT_ADMIN can grant the role for governance rotation.

## Why 7 days (and not shorter / longer)

The trade-off is between provider protection and keeper burden:

| Window | Provider protection | Keeper burden | Notes |
|---|---|---|---|
| < 1 day | Aggressive — even a 6-hour oracle outage strands signals. | High — every short blip requires keeper intervention. | Too tight; routine multi-hour keeper outages become incidents. |
| 1–3 days | Catches most outage scenarios, but still tight. | Medium — keepers reconcile daily. | Reasonable, but punishes 4-day weekend + holiday outages. |
| **7 days (chosen)** | Tolerates a full week of keeper silence (the protocol's documented worst-case window for the recorder-ledger 30-day outage pattern). | Low — keepers reconcile weekly. | Matches the cadence of the engine's alert-escalation (Discord immediate, Resend after 6h, SMS after 24h) — by the time all three escalate and a human responds, a 7-day window still has slack. |
| > 14 days | Permissive. | Very low. | Strands signals too long for a "recovery" claim to feel like recovery; users lose trust in the signal pipeline. |

The chosen 7-day window is the **same order of magnitude as the whitepaper §6.4
"long-tail risk" section** which names multi-day keeper outages as a class the
protocol tolerates by design. It is also short enough that a permanently-dead
oracle does not strand signals for a full mainnet launch cycle.

## Why no fee on release

`claimExpiredSignal` does not slash the provider because **nothing was ever taken**.
A never-scored signal never triggered `applyPayout`, so there is no payout to
reverse. Charging a fee here would be taxing the provider for the oracle's failure
— economically wrong, and inconsistent with the rest of the protocol (the keeper
is trusted, the provider is not). Off-chain observers can detect a pattern of
"submit-then-walk-away" signals if they care; the on-chain contract does not
enforce it.

## Why gate on `EPOCH_SETTLER` (not provider self-service)

A provider-controlled release would let an adversary submit signals and self-clear
them before the oracle has had a chance to score. The keeper-gated model ensures
human-or-automation review before a signal is released; the `MAX_SIGNAL_AGE`
window is the consumer-protection half (providers know exactly when release is
possible and can complain off-chain if the keeper is delinquent).
