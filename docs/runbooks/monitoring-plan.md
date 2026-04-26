# Monitoring Plan (Minimum Viable) — Testnet

## Goals

- Detect privileged role changes and pauses immediately
- Detect unusual trade execution patterns
- Detect repeated rejected signals (potential abuse)

## What to monitor

### On-chain events (index via explorer API / RPC logs)

- **StrategyExecutor**
  - `PausedSet` (or equivalent)
  - `SignalRejected` / invalid signature events (if emitted)
  - any `RoleGranted` / `RoleRevoked`
- **Vaults**
  - `TradeExecuted` / equivalent
  - circuit breaker activation event (if emitted)
- **Governance / Timelock**
  - proposal queued/executed
  - timelock operation executed/cancelled

### Application signals

- API: `/api/signals/execute`
  - count 2xx vs 4xx/5xx
  - rate limit hits (429)
  - unauthorized hits (401)

## Alerts (initial thresholds)

- **A1**: Any pause event → page IC immediately
- **A2**: Any role grant/revoke → page IC immediately
- **A3**: >5 rejected signals per hour → notify protocol eng
- **A4**: >10 execute attempts per minute from one IP (429 triggered) → notify security

## Evidence for Verification Gate G9

To prove alerts “fire correctly” on testnet:

1. Trigger a benign test event (e.g., pause/unpause in a controlled environment)
2. Capture the alert delivery evidence (screenshot/log)
3. Record tx hash + timestamp

