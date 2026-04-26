# Zentory Protocol — Deployment Guide

## Overview

The protocol deploys in five phases, wired together by `DeployPipeline.s.sol`.
All contracts are deployed on **HyperEVM** (Chain ID: 9999 for testnet, 7777 for mainnet).

---

## Phase 1 — Core Tokens

```bash
forge script script/DeployCore.s.sol --rpc-url $HYPEREVM_RPC --private-key $PRIVATE_KEY --broadcast
```

**Contracts deployed:**
- `ZENT` — ERC-20 token, 1B supply, no mint function, Soul-bound voting delegation
- `ZENTVesting` — Programmatic vesting for team (180M, 18-month cliff, 18-month linear) and backers (150M, 6-month cliff, 12-month linear)

**Outputs:**
- `broadcast/DeployCore.s.sol/<chain>/run-latest.json`
- `deployments.json` key `ZENT`, `ZENT_VESTING`

---

## Phase 2 — Alpha Vaults

```bash
forge script script/DeployVaults.s.sol --rpc-url $HYPEREVM_RPC --private-key $PRIVATE_KEY --broadcast
```

**Contracts deployed:**
- `zETHVault` — WETH vault, ERC-4626
- `zBTCVault` — WBTC vault, ERC-4626
- `zXRPVault` — XRP vault, ERC-4626
- `zSOLVault` — SOL vault, ERC-4626

**Dependencies:** `ZENT` address

**Outputs:**
- `deployments.json` keys `Z_ETH_VAULT`, `Z_BTC_VAULT`, `Z_XRP_VAULT`, `Z_SOL_VAULT`

---

## Phase 3 — Staking & Bonding

```bash
forge script script/DeployStaking.s.sol --rpc-url $HYPEREVM_RPC --private-key $PRIVATE_KEY --broadcast
```

**Contracts deployed:**
- `ZENTStaking` — veZENT staking (7-day min, 730-day max lock)
- `ModelBonding` — Bonding for signal providers (7-day cooldown)
- `FeeDistributor` × 4 — One per vault asset (ETH, BTC, XRP, SOL)

**Dependencies:** `ZENT`, Governor address

**Fee split** (set per FeeDistributor at deployment, defaults shown):
- 50% → buyback & burn (ZENT)
- 25% → GP engine (signal provider reward)
- 15% → insurance pool
- 10% → treasury

**Outputs:**
- `deployments.json` keys `ZENT_STAKING`, `MODEL_BONDING`, `Z_ETH_FEES`, `Z_BTC_FEES`, `Z_XRP_FEES`, `Z_SOL_FEES`

---

## Phase 4 — Governance

```bash
forge script script/DeployGovernance.s.sol --rpc-url $HYPEREVM_RPC --private-key $PRIVATE_KEY --broadcast
```

**Contracts deployed:**
- `Timelock` — 48-hour delay timelock
- `Zentroller` — Linkage contract resolving ZENT staking address for the governor (no pause capability)
- `ZentGovernor` — DAO with 2-day voting delay, 7-day voting period

**Dependencies:** `ZENT`, `ZENTStaking`

**Outputs:**
- `deployments.json` keys `TIMELOCK`, `ZENTROLLER`, `ZENT_GOVERNOR`

---

## Phase 5 — Keeper / Executor

```bash
forge script script/DeployKeeper.s.sol --rpc-url $HYPEREVM_RPC --private-key $PRIVATE_KEY --broadcast
```

**Contracts deployed:**
- `HyperCoreAdapter` — HyperEVM → HyperCore order gateway
- `StrategyExecutor` — ECDSA-signed signal execution with nonce replay protection

**Dependencies:** Governor address

**Outputs:**
- `deployments.json` keys `HYPERCORE_ADAPTER`, `STRATEGY_EXECUTOR`

---

## Full Pipeline (Single Command)

Deploy everything in one shot:

```bash
forge script script/DeployPipeline.s.sol --rpc-url $HYPEREVM_RPC --private-key $PRIVATE_KEY --broadcast -vvv
```

---

## Post-Deployment Wiring

After deployment, the pipeline script performs these wiring steps automatically:

1. **Governor granted roles** on all contracts
2. **Risk limits set** on `StrategyExecutor` for each vault (max leverage 3×)
3. **KEEPER_ROLE** granted to the keeper address
4. **GUARDIAN_ROLE** granted to the guardian address

To wire manually or verify:

```bash
# Verify governor is admin of all contracts
forge script script/VerifyRoles.s.sol --rpc-url $HYPEREVM_RPC -vvv
```

---

## Required Environment Variables

```bash
# .env file (copy from .env.example)
PRIVATE_KEY=0x...          # Deployer private key
HYPEREVM_RPC=https://...   # HyperEVM RPC URL
ETHERSCAN_API_KEY=...       # For verification (optional)
```

---

## Contract Addresses (Mainnet)

| Contract | Address |
|---|---|
| ZENT | `TBD` |
| ZENTVesting | `TBD` |
| zETHVault | `TBD` |
| zBTCVault | `TBD` |
| zXRPVault | `TBD` |
| zSOLVault | `TBD` |
| ZENTStaking | `TBD` |
| ModelBonding | `TBD` |
| FeeDistributor (ETH) | `TBD` |
| FeeDistributor (BTC) | `TBD` |
| FeeDistributor (XRP) | `TBD` |
| FeeDistributor (SOL) | `TBD` |
| Timelock | `TBD` |
| Zentroller | `TBD` |
| ZentGovernor | `TBD` |
| HyperCoreAdapter | `TBD` |
| StrategyExecutor | `TBD` |

---

## Risk Parameters

| Parameter | Value |
|---|---|
| Max leverage (all vaults) | 30000 BPS (3×) |
| Performance fee | 20% (BaseVault) |
| Min stake (ZENTStaking) | 1,000 ZENT |
| Min lock (ZENTStaking) | 7 days |
| Max lock (ZENTStaking) | 730 days |
| Unbond cooldown (ModelBonding) | 7 days |

---

## Verification

```bash
# Run full test suite first
forge test

# Run static analysis
slither . --solc-remaps '@openzeppelin=node_modules/@openzeppelin'

# Verify on Blockscout
forge verify-contract <CONTRACT_ADDRESS> src/.../*.sol:ContractName \
  --chain hyperEVM --verifier blockscout \
  --verifier-url https://evm.l2scan.co/api
```
