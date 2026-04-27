# Monitoring Setup Guide — G9 / G10 Evidence

This guide sets up on-chain monitoring using a lightweight Python script that polls
the HyperEVM RPC directly — no external service (Tenderly/Defender) required.

---

## Why This Approach?

| Tool | HyperEVM Support | Cost |
|------|----------------|------|
| Tenderly | No | Free tier |
| OpenZeppelin Defender | Shutting down July 2026 | N/A |
| **Custom Monitor** | Any chain | Free (just RPC calls) |

The monitor uses `eth_getLogs` which is free on public RPC endpoints and works
with any EVM-compatible chain.

---

## Step 1 — Get a Discord Webhook

1. Open Discord → right-click your server → **Edit Server**
2. Go to **Integrations → Webhooks** → **New Webhook**
3. Name it `Zentory Alerts` and copy the webhook URL
4. It looks like: `https://discord.com/api/webhooks/...`

---

## Step 2 — Install Dependencies

```bash
cd ZentoryToken/engine
pip install -e ".[dev]"
```

Required packages: `web3`, `structlog`, `httpx`

---

## Step 3 — Test the Monitor

```bash
# Send a test alert to your Discord channel
python -m monitor.event_monitor --test --discord-webhook "YOUR_DISCORD_WEBHOOK_URL"
```

You should see a green "Zentory Monitor" test alert in your Discord channel.

---

## Step 4 — Run the Monitor

### Option A: Run in background (PowerShell)

```powershell
$env:DISCORD_WEBHOOK_URL = "YOUR_DISCORD_WEBHOOK_URL"
python -m monitor.event_monitor --poll-interval 30
```

### Option B: Run as a background service

```bash
# On Linux/macOS with systemd
cp deploy/monitor/zentory-monitor.service /etc/systemd/system/
systemctl enable zentory-monitor
systemctl start zentory-monitor

# View logs
journalctl -u zentory-monitor -f
```

### Option C: Run with PM2 (Node.js ecosystem alternative)

```bash
pm2 start --name zentory-monitor "python -m monitor.event_monitor --poll-interval 30"
pm2 save
pm2 startup
```

---

## Step 5 — Verify Past Events (G9 Evidence)

The monitor will immediately scan past blocks and fire alerts for events
already on-chain. Run it once and capture the Discord notifications:

```bash
python -m monitor.event_monitor --poll-interval 30
```

Look for these historical events that were already fired:

| Event | TX Hash | Block |
|-------|---------|-------|
| PausedSet(true) | `0x89d821...` | 51978896 |
| PausedSet(false) | `0xce90d7...` | 51978957 |

**Screenshot your Discord channel** — those alerts are your G9 evidence.

---

## Alert Severity Reference

| Severity | Event | Discord Color |
|----------|-------|--------------|
| CRITICAL | `PausedSet(bool)` on StrategyExecutor | Red |
| CRITICAL | `RoleGranted` / `RoleRevoked` on any contract | Red |
| HIGH | `CircuitBreakerActivated` on any vault | Orange |
| MEDIUM | `FeesDistributed` on FeeDistributor | Yellow |
| LOW | `ManualTradeRecorded`, `Staked`, `Withdraw` | Green |

---

## All Monitored Contracts

| Contract | Address |
|----------|---------|
| ZENT | `0x271cd48...` |
| ZENTVesting | `0xf7c45f...` |
| zETH Vault | `0xbe8a9d...` |
| zBTC Vault | `0x93669d...` |
| zXRP Vault | `0x8B15204...` |
| zSOL Vault | `0xb62BA9d...` |
| ZENTStaking | `0x4E2e7F...` |
| FeeDistributor (zETH) | `0x8Fb48F...` |
| FeeDistributor (zBTC) | `0x403e8C...` |
| FeeDistributor (zXRP) | `0xC69f8a...` |
| FeeDistributor (zSOL) | `0xE990BF...` |
| Timelock | `0x1504cA...` |
| Zentroller | `0x24f9401...` |
| ZentGovernor | `0x21ba1F...` |
| HyperCoreAdapter | `0xfFc1Da...` |
| StrategyExecutor | `0x427c941...` |

---

## G9 / G10 Evidence Collection

### G9 — Alert Firing Proof

1. Run `python -m monitor.event_monitor --test` to confirm Discord notifications work
2. Run the monitor with your webhook — it will immediately fire alerts for the
   `PausedSet` events from blocks 51978896 and 51978957
3. Screenshot the Discord alert in your channel
4. Save to `docs/reports/g9-alert-evidence-2026-04-27/`

### G10 — Runbook Test

1. Confirm Discord alert arrived within 5 minutes of running the monitor
2. Screenshot the alert showing severity (CRITICAL) and tx hash
3. Document the response time
4. Save to `docs/reports/g10-runbook-test-2026-04-27/`

---

## Monitoring Events (Complete List)

The monitor tracks these event signatures:

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

---

## Troubleshooting

**No events appearing:**
- Verify your RPC URL is accessible: `curl -X POST https://rpc.hyperliquid-testnet.xyz/evm -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'`
- Check the Discord webhook is valid
- Run with `--from-block 51978896` to force a specific starting block

**Getting rate limited:**
- Increase `--poll-interval` to 60 seconds
- The monitor deduplicates events so you'll never miss anything

**Want to add more events:**
- Add the event signature hash to `EVENT_SIGNATURES` in `event_monitor.py`
- Get the signature with: `cast sig "EventName(arg1,arg2)"`
