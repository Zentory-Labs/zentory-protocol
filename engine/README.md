# Zentory Engine — Phase 1 Usage

## Quick Start

```bash
cd engine
pip install -e ".[dev]"
```

## Post a signal to Supabase (via dApp API)

```bash
# Set your dApp URL
export DAPP_URL=https://app.zentorylabs.com

# Post a LONG signal for BTC
python -m execution.lumibot_broker --asset BTC --direction LONG --size 0.01 --price 67000

# Post and immediately execute on-chain
python -m execution.lumibot_broker --asset ETH --direction LONG --size 1.0 --price 3500 --execute
```

## Architecture

```
Lumibot / Manual Indicator
        ↓
LumibotBroker.post_signal()   →  POST /api/signals  →  Supabase
                                                              ↓
                                    Signal Dashboard (dApp) ← reads from Supabase
                                                              ↓
LumibotBroker.execute_signal() →  POST /api/signals/execute  →  StrategyExecutor (on-chain)
```

## Vault Addresses (HyperEVM Testnet)

| Asset | Vault Address |
|-------|--------------|
| BTC   | 0x07b4DeB8A3B4CF656276312e2BF63E9927bfBc97 |
| ETH   | 0x8367449CFEE8f8eA15Daf91B8A535F55687D3aC0 |
| XRP   | 0xe75421E0d7322188F98cBdb1211F2fED9285bb9d |
| SOL   | 0x6c5aBE91Fe5364022DAB20A5b8Ac4F34285FdDD9 |

## Phase 2 — GP Engine

```bash
# Run GP evolution loop
python -m execution.main
```
