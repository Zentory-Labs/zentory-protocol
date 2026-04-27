# Monitoring Plan (Minimum Viable) — Testnet

## Goals

- Detect privileged role changes and pauses immediately
- Detect unusual trade execution patterns
- Detect repeated rejected signals (potential abuse)

## Monitoring Tool: Custom Event Monitor

Tenderly does not support HyperEVM. OpenZeppelin Defender is shutting down (July 2026).
The protocol uses a lightweight **custom Python monitor** (`engine/src/monitor/event_monitor.py`)
that polls the HyperEVM RPC directly via `eth_getLogs` — no API key or external service required.

See `docs/runbooks/monitoring-setup.md` for setup instructions.

### How it works

- Polls `eth_getLogs` every N seconds (default: 30s)
- Matches event signatures for all 21 deployed contracts
- Sends Discord/Slack webhook alerts for CRITICAL events immediately
- Maintains a local state file (`.monitor_state.json`) to track last block checked
- Dedupes events by tx hash + log index

### On-chain events monitored

- **StrategyExecutor**: `PausedSet(bool)`, `RoleGranted`, `RoleRevoked`, `ManualTradeRecorded`
- **All 4 Vaults**: `CircuitBreakerActivated`, `CircuitBreakerAutoTriggered`, `Deposit`, `Withdraw`
- **FeeDistributors**: `FeesDistributed`, `Accumulated`
- **ZENTStaking**: `Staked`, `Withdrawn`
- **ZentGovernor**: `ProposalCreated`, `VoteCast`

### Alert thresholds

- **A1**: `PausedSet(true)` on StrategyExecutor -> CRITICAL (Discord red) + page IC immediately
- **A2**: Any `RoleGranted`/`RoleRevoked` -> CRITICAL (Discord red) + page IC immediately
- **A3**: >5 `SignalRejected` per hour -> notify protocol eng
- **A4**: >10 rate-limited API calls per minute from one IP -> notify security

## Evidence for Verification Gate G9

To prove alerts fire correctly on testnet:

1. Run the monitor with your Discord webhook
2. It will immediately fire alerts for historical events already on-chain
3. Capture Discord notification screenshots as evidence

## Implementation Status

| Component | Status | Notes |
|-----------|--------|-------|
| `monitoring-plan.md` (this doc) | **Done** | Plan defined |
| `incident-response.md` | **Done** | Runbook complete |
| On-chain event monitor | **Done** | `engine/src/monitor/event_monitor.py` |
| Alert routing (A1-A4) | **READY** | Discord webhook only (setup in monitoring-setup.md) |
| API rate-limit alerting | **WIRED** | 401 responses logged; rate limit returns 429 |
| G9 evidence (alert test) | **READY** | Run monitor; Discord alerts fire for historical events |
| G10 evidence (runbook tested) | **READY** | Controlled pause/unpause executed; run monitor for evidence |

**On-chain events fired (G9/G10 prerequisite)**:
- Pause: `0x89d821c0c53d02f6d5fbfbdcbde4de6a8b54bbe872f02ef66887a2ba44e41d56` (block 51978896)
- Unpause: `0xce90d74a0d803970ad59c0e4bd3d8fb85afaed254c8edef1682cc5ded8d26563` (block 51978957)

**Setup guide**: `docs/runbooks/monitoring-setup.md` — step-by-step Discord webhook setup and monitor usage.
