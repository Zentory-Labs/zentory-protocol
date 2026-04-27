# Monitoring Setup Guide — G9 / G10 Evidence

This guide sets up on-chain monitoring using a lightweight Python script that polls
the HyperEVM RPC directly — no external service (Tenderly/Defender) required.

---

## Why This Approach?

| Tool | HyperEVM Support | Status |
|------|-----------------|--------|
| Tenderly | No | Not supported |
| OpenZeppelin Defender | Shutting down July 2026 | Disabled new signups |
| **Custom Monitor + Alchemy** | Any EVM chain | Free tier, unlimited logs |

The monitor uses `eth_getLogs` which is free on Alchemy's HyperEVM tier
(5M compute units/month free). The public RPC works for testing but is
rate-limited for production use.

---

## Step 1 — Get an Alchemy API Key (Free, 5 min)

1. Go to https://www.alchemy.com/hyperevm
2. Sign up (free — no credit card)
3. Create an app: **App Type = HyperEVM**, **Network = Hyperliquid Testnet**
4. Copy your **API Key** (something like `abc123def456`)

---

## Step 2 — Get a Discord Webhook

1. Open Discord → right-click your server → **Edit Server**
2. Go to **Integrations → Webhooks** → **New Webhook**
3. Name it `Zentory Alerts` and copy the webhook URL

---

## Step 3 — Install Dependencies

```bash
cd ZentoryToken/engine
pip install -e ".[dev]"
```

Required: `web3`, `structlog`, `httpx` (all in `pyproject.toml`)

---

## Step 4 — Test the Monitor

```bash
# Send a test alert to your Discord channel
python -m monitor.event_monitor \
  --discord-webhook "YOUR_DISCORD_WEBHOOK_URL" \
  --test
```

You should see a green "Zentory Monitor" test alert in your Discord channel.

---

## Step 5 — Run the Monitor

### With Alchemy (recommended for production)

```bash
python -m monitor.event_monitor \
  --alchemy-api-key "YOUR_ALCHEMY_KEY" \
  --discord-webhook "YOUR_DISCORD_WEBHOOK_URL" \
  --poll-interval 30
```

### With public RPC (rate-limited — fine for testing)

```bash
python -m monitor.event_monitor \
  --discord-webhook "YOUR_DISCORD_WEBHOOK_URL" \
  --poll-interval 60
```

### Run in background (PowerShell)

```powershell
$env:DISCORD_WEBHOOK_URL = "YOUR_DISCORD_WEBHOOK_URL"
$env:ALCHEMY_API_KEY = "YOUR_ALCHEMY_KEY"
python -m monitor.event_monitor --poll-interval 30
```

---

## Step 6 — G9 Evidence Collection

The monitor will immediately scan past blocks and fire alerts for the
`PausedSet` events already on-chain. Run it and screenshot Discord:

```bash
python -m monitor.event_monitor \
  --alchemy-api-key "YOUR_ALCHEMY_KEY" \
  --discord-webhook "YOUR_DISCORD_WEBHOOK_URL"
```

You should see **two CRITICAL (red) alerts** appear immediately:

| Event | TX Hash | Block |
|-------|---------|-------|
| PausedSet(true) | `0x89d821...` | 51978896 |
| PausedSet(false) | `0xce90d7...` | 51978957 |

Screenshot both Discord alerts and save to `docs/reports/g9-alert-evidence-2026-04-27/`.

---

## G10 Evidence — Runbook Test

1. Confirm the Discord CRITICAL alerts arrived within ~30 seconds of starting the monitor
2. Screenshot the alerts showing:
   - CRITICAL severity (red embed)
   - `PausedSet` event name
   - Contract: StrategyExecutor
   - TX hash matches `0x89d821...`
3. Save to `docs/reports/g10-runbook-test-2026-04-27/`

---

## Alert Severity Reference

| Severity | Discord Color | Events |
|----------|--------------|--------|
| CRITICAL | Red | `PausedSet(bool)`, `RoleGranted`, `RoleRevoked` |
| HIGH | Orange | `CircuitBreakerActivated`, `CircuitBreakerAutoTriggered` |
| MEDIUM | Yellow | `FeesDistributed`, `Accumulated` |
| LOW | Green | `ManualTradeRecorded`, `Staked`, `Withdrawn` |

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

## CLI Options

```bash
python -m monitor.event_monitor [OPTIONS]

  --alchemy-api-key KEY   Alchemy API key (free at alchemy.com/hyperevm)
  --discord-webhook URL   Discord webhook URL
  --rpc-url URL           Custom RPC URL (overrides --alchemy-api-key)
  --poll-interval SECONDS Seconds between polls (default: 30)
  --from-block NUMBER     Start from this block (default: last saved)
  --test                  Send test alert and exit
```

---

## Troubleshooting

**Getting rate limited:**
- Use `--alchemy-api-key` (Alchemy free tier has 5M compute units/month)
- Increase `--poll-interval` to 60 seconds

**No events appearing:**
- Verify Alchemy key is correct: `curl https://eth-hyperliquid-YOUR_KEY.g.alchemy.com/evm -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'`
- Verify Discord webhook is valid
- Run with `--from-block 51978896` to force starting from the event block

**Monitor running but missing events:**
- Check the state file: `engine/src/monitor/.monitor_state.json`
- Delete it and re-run to rescan from `from_block`
