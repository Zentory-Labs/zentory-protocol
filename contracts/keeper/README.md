# ZENT Protocol Epoch Scoring Keeper

Production-ready Node.js keeper script that automates the 4-hour epoch scoring and payout cycle for the ZENT Protocol on HyperEVM Testnet.

## Overview

The keeper bot:
1. Checks if the epoch is ready to settle (every 4 hours)
2. Fetches all active signals from Supabase within the epoch window
3. Computes Numerai-style accuracy scores using CoinGecko price data
4. Caches accuracy on-chain via `EpochScoring.setAccuracy()`
5. Applies payouts via `EpochScoring.applyPayout()`
6. Settles the epoch on-chain via `EpochScoring.settleEpoch()`
7. Persists results to Supabase for the frontend
8. Writes audit logs for traceability

## Prerequisites

- Node.js 20+
- npm or yarn
- Access to HyperEVM Testnet RPC (https://rpc.testnet.hyperliquid.xyz)
- Keeper wallet with ETH for gas
- Supabase project with the required tables

## Setup

```bash
# Navigate to the keeper directory
cd contracts/keeper

# Install dependencies
npm install

# Copy environment template
cp .env.example .env

# Edit .env with your values
# Required:
#   - HYPEREVM_RPC_URL
#   - KEEPER_PRIVATE_KEY (with ETH for gas)
#   - SUPABASE_URL
#   - SUPABASE_SERVICE_ROLE_KEY
#   - Contract addresses (pre-filled for HyperEVM Testnet)
```

## Supabase Schema Requirements

The keeper expects the following tables in Supabase:

### `signals`
| Column       | Type      | Description                    |
|--------------|-----------|--------------------------------|
| id           | text      | Unique signal ID (bytes32 hex) |
| provider     | text      | Provider wallet address        |
| asset_class  | text      | CRYPTO_SPOT, CRYPTO_PERP, etc. |
| asset_id     | text      | Asset symbol (BTC, ETH, etc.)   |
| direction    | integer   | -10000 to 10000                |
| confidence   | integer   | 0 to 10000                     |
| expires_at   | bigint    | Unix timestamp                 |
| submitted_at | bigint    | Unix timestamp                 |
| status       | text      | 'Active' or 'Resolved'         |

### `epoch_history`
| Column           | Type  | Description                       |
|------------------|-------|----------------------------------|
| epoch_id         | integer | Epoch number                    |
| start_time       | bigint  | Epoch start Unix timestamp     |
| end_time         | bigint  | Epoch end Unix timestamp       |
| total_signals    | integer | Total signals in epoch         |
| settled_signals  | integer | Successfully settled signals    |
| avg_accuracy_bps | integer | Average accuracy (basis points) |

### `signal_scores`
| Column       | Type    | Description                    |
|--------------|---------|--------------------------------|
| signal_id    | text    | Signal ID                      |
| epoch_id     | integer | Epoch number                   |
| accuracy_bps | integer | Accuracy score (basis points)  |
| payout_zent  | text    | Payout amount in ZENT (string) |

### `provider_stats`
| Column       | Type    | Description                    |
|--------------|---------|--------------------------------|
| provider     | text    | Provider wallet address        |
| epoch_id     | integer | Epoch number                   |
| accuracy_bps | integer | Accuracy score (basis points)  |
| payout_zent  | text    | Payout amount in ZENT (string) |

### `audit_logs`
| Column    | Type   | Description                     |
|-----------|--------|---------------------------------|
| actor     | text   | 'keeper' or wallet address     |
| action    | text   | Action type                     |
| payload   | jsonb  | Action payload                  |
| timestamp | bigint | Unix timestamp                  |

## Running

### Development
```bash
npm run dev
```

### Production
```bash
npm run build
npm start
```

## Cron Scheduling

Run the keeper every 4 hours using cron:

```cron
0 */4 * * * cd /path/to/contracts/keeper && npm start >> /var/log/keeper.log 2>&1
```

Or with systemd timer:

```ini
# /etc/systemd/system/zent-keeper.timer
[Timer]
OnCalendar=*:0/4
Persistent=true

[Install]
WantedBy=timers.target
```

```ini
# /etc/systemd/system/zent-keeper.service
[Service]
Type=oneshot
WorkingDirectory=/path/to/contracts/keeper
ExecStart=/path/to/contracts/keeper/dist/index.js
Environment=NODE_ENV=production
```

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Keeper Bot                          │
├─────────────────────────────────────────────────────────┤
│  index.ts — Main loop, orchestrates all steps          │
│  chain.ts  — Viem client, on-chain reads/writes        │
│  scoring.ts — Numerai accuracy formula, price fetcher   │
│  supabase.ts — DB reads/writes                         │
│  config.ts — Env validation                           │
│  types.ts — TypeScript interfaces                     │
└──────────────────┬──────────────────────────────────────┘
                   │
     ┌─────────────┼─────────────┐
     ▼             ▼             ▼
┌─────────┐  ┌─────────┐  ┌──────────┐
│HyperEVM │  │Supabase │  │CoinGecko │
│ RPC     │  │         │  │API       │
└─────────┘  └─────────┘  └──────────┘
```

## Error Handling

- Individual signal failures are logged but do not crash the keeper
- The keeper will continue processing remaining signals
- Failed signals are counted and reported in the audit log
- Transaction confirmations are awaited before proceeding

## Monitoring

Logs are written to stdout in JSON format for easy parsing:

```json
{
  "status": "success",
  "epochId": 42,
  "totalSignals": 10,
  "settledSignals": 9,
  "failedSignals": 1,
  "avgAccuracyBps": 5450,
  "settleTx": "0x..."
}
```

Redirect to a log file in production:
```bash
npm start >> /var/log/zent-keeper.log 2>&1
```

## Accuracy Formula

Numerai-style scoring:
- `accuracyBps = 5000 + (direction / 10000) * priceChangeBps`
- Long signals (direction >= 0): correct when price rises
- Short signals (direction < 0): correct when price falls
- Result clipped to [0, 10000]

## Contract Addresses (HyperEVM Testnet)

| Contract       | Address                                    |
|----------------|--------------------------------------------|
| SignalRegistry | 0x7745B22B2C73E422154Fcd1ECD283765c4BF6e8c |
| EpochScoring   | 0xB6b206AaF3a482624238dD8292BB63EDBAf59143 |
| ZENTStaking    | 0x4E2e7Fd3C85c05697b24743e580B03abCD6d0c65 |
| ZENT Token     | 0x271cd48c1297CacCD810c7B1BCD904f459df7117 |

RPC: https://rpc.testnet.hyperliquid.xyz
Chain ID: 998
