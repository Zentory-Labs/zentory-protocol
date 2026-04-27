# Monitoring Plan (Minimum Viable) — Testnet

## Goals

- Detect privileged role changes and pauses immediately
- Detect unusual trade execution patterns
- Detect repeated rejected signals (potential abuse)

## Monitoring Tool

**Custom Python Event Monitor** + **Alchemy** + **Discord**

Tenderly does not support HyperEVM. OpenZeppelin Defender is shutting down (July 2026).
The protocol uses a lightweight Python monitor (`engine/src/monitor/event_monitor.py`)
that polls HyperEVM via `eth_getLogs` using an Alchemy API key (free tier, 5M units/month).

### How it works

- Polls `eth_getLogs` every N seconds (default: 30s) across all 17 contracts
- Matches event signatures for critical events
- Sends color-coded Discord webhook alerts (red=CRITICAL, orange=HIGH, etc.)
- Maintains local state (`.monitor_state.json`) for deduplication and resumption
- Rate-limit aware with automatic backoff

### On-chain events monitored

| Event | Contract(s) | Severity |
|-------|------------|---------|
| `PausedSet(bool)` | StrategyExecutor | CRITICAL |
| `RoleGranted(bytes32,address)` | All contracts | CRITICAL |
| `RoleRevoked(bytes32,address)` | All contracts | CRITICAL |
| `CircuitBreakerActivated` | All 4 vaults | HIGH |
| `CircuitBreakerAutoTriggered` | All 4 vaults | HIGH |
| `ManualTradeRecorded` | StrategyExecutor | LOW |
| `FeesDistributed` | FeeDistributors | MEDIUM |
| `Accumulated` | FeeDistributors | MEDIUM |
| `Staked` | ZENTStaking | LOW |
| `Withdrawn` | ZENTStaking | LOW |

### Alert thresholds

- **A1**: `PausedSet(true)` on StrategyExecutor -> CRITICAL (Discord red) + page IC immediately
- **A2**: Any `RoleGranted`/`RoleRevoked` -> CRITICAL (Discord red) + page IC immediately
- **A3**: >5 `SignalRejected` per hour -> notify protocol eng
- **A4**: >10 rate-limited API calls per minute from one IP -> notify security

## Evidence for Verification Gate G9

To prove alerts fire correctly on testnet:

1. Run the monitor with your Alchemy API key + Discord webhook
2. It immediately fires alerts for historical `PausedSet` events already on-chain
3. Capture Discord notification screenshots as evidence

## Implementation Status

| Component | Status | Notes |
|-----------|--------|-------|
| `monitoring-plan.md` (this doc) | **Done** | Plan defined |
| `incident-response.md` | **Done** | Runbook complete |
| On-chain event monitor | **Done** | `engine/src/monitor/event_monitor.py` |
| Alchemy integration | **Ready** | Free tier at alchemy.com/hyperevm |
| Discord webhook alerts | **Ready** | Color-coded by severity |
| API rate-limit alerting | **WIRED** | 401 responses logged; rate limit returns 429 |
| G9 evidence (alert test) | **READY** | Run monitor with Alchemy; Discord alerts fire for historical events |
| G10 evidence (runbook tested) | **READY** | Controlled pause/unpause executed; monitor provides evidence |

**On-chain events fired (G9/G10 prerequisite)**:
- Pause: `0x89d821c0c53d02f6d5fbfbdcbde4de6a8b54bbe872f02ef66887a2ba44e41d56` (block 51978896)
- Unpause: `0xce90d74a0d803970ad59c0e4bd3d8fb85afaed254c8edef1682cc5ded8d26563` (block 51978957)

**Setup guide**: `docs/runbooks/monitoring-setup.md` -- step-by-step Alchemy + Discord webhook setup and monitor usage.
