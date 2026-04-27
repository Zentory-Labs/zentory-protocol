# G9 Evidence — Monitoring Alert Test
Date: 2026-04-27
Tool: Custom Python monitor (`engine/src/monitor/event_monitor.py`)

## On-Chain Events Triggered

### PausedSet Event (A1-Critical Alert)

**Contract**: StrategyExecutor (0x427c94150f3f700Dc2EDf7bCc97155A467E41F21)
**Chain**: HyperEVM Testnet (chain 998)

| Action | Tx Hash | Block | Timestamp |
|--------|---------|-------|-----------|
| Pause (true) | 0x89d821c0c53d02f6d5fbfbdcbde4de6a8b54bbe872f02ef66887a2ba44e41d56 | 51978896 | 2026-04-27T08:43:52Z |
| Unpause (false) | 0xce90d74a0d803970ad59c0e4bd3d8fb85afaed254c8edef1682cc5ded8d26563 | 51978957 | 2026-04-27T08:45:02Z |

**Event Signature**: `PausedSet(bool paused)`
- Signature hash: `0x40db37ff5c0bdc2c427fbb2078c8f24afea940abac0e3c23bb4ea3bf2da2b212`

## How to Run the Monitor

```bash
# Install dependencies
cd ZentoryToken/engine
pip install -e ".[dev]"

# Run the monitor (fires alerts for all historical events + live events)
python -m monitor.event_monitor --discord-webhook "YOUR_DISCORD_WEBHOOK_URL"
```

The monitor will IMMEDIATELY find the two historical PausedSet events above
when started (it scans from last saved block on startup).

## Event Log (raw from RPC)

```json
{
  "address": "0x427c94150f3f700dc2edf7bcc97155a467e41f21",
  "topics": [
    "0x40db37ff5c0bdc2c427fbb2078c8f24afea940abac0e3c23bb4ea3bf2da2b212"
  ],
  "data": "0x0000000000000000000000000000000000000000000000000000000000000001",
  "blockNumber": "0x3192290",
  "blockTimestamp": "0x69ef21d0",
  "transactionHash": "0x89d821c0c53d02f6d5fbfbdcbde4de6a8b54bbe872f02ef66887a2ba44e41d56"
}
```

## Verification Commands

```bash
# Verify pause state on-chain
cast call 0x427c94150f3f700Dc2EDf7bCc97155A467E41F21 \
  "paused()" \
  --rpc-url https://rpc.hyperliquid-testnet.xyz/evm

# Get event signature
cast sig-event "PausedSet(bool)"
# Result: 0x40db37ff5c0bdc2c427fbb2078c8f24afea940abac0e3c23bb4ea3bf2da2b212

# Fetch raw logs for the event
cast logs --from-block 51978896 --to-block 51978896 \
  --address 0x427c94150f3f700Dc2EDf7bCc97155A467E41F21 \
  --rpc-url https://rpc.hyperliquid-testnet.xyz/evm
```

## G9 Evidence to Collect

1. Run: `python -m monitor.event_monitor --discord-webhook "YOUR_WEBHOOK" --poll-interval 30`
2. You should immediately see two CRITICAL alerts in Discord (red) — one for pause, one for unpause
3. **Screenshot** the Discord channel showing both alerts
4. Save to `docs/reports/g9-alert-evidence-2026-04-27/`
   - `discord-alert-paused.png` — CRITICAL alert for 0x89d821...
   - `discord-alert-unpaused.png` — alert for 0xce90d7...
