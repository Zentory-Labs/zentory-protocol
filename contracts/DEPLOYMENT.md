# Zentory Protocol — Deployment Guide

## Overview

The protocol deploys in six phases via `DeployPipeline.s.sol` (full deploy) or `ResumeDeployment.s.sol` (catch-up).
All contracts are deployed on **HyperEVM** (Chain ID: 998 for testnet, 7777 for mainnet).

## Verified Testnet Deployment (HyperEVM Testnet, Chain 998)

Deployed by `0x3F07367008158dC272Dd8A38812e1460eF5a390a` on 2026-04-27:

| Contract | Address |
|---|---|
| ZENT | `0x271cd48c1297CacCD810c7B1BCD904f459df7117` |
| ZENTVesting | `0xf7c45f45768d790F388215A44d6E01f6f2568774` |
| WETH (mock) | `0x80F727AF3f7932718fEb25FC28818Ad103040BD2` |
| WBTC (mock) | `0x08890A5B7D6D157Da65C04C19150fF7d124eaE40` |
| WXRP (mock) | `0xe1Fe75622Bd5D962c72c1D0A621E5fa6656a4371` |
| WSOL (mock) | `0x2b9d5bBD8C5FEfc71E985d993C13db2770469972` |
| zETH Vault | `0xbe8a9d22560A1b126554b70Aaca2D763B2E70C4e` |
| zBTC Vault | `0x93669daC07321FF397cf5734Ae8364EA24addF45` |
| zXRP Vault | `0x8B15204D88a9Bb155bE6798522983A3B5F7d7cB0` |
| zSOL Vault | `0xb62BA9d0a14aC9f9601891179B3Da52bE71Ce052` |
| ZENTStaking | `0x4E2e7Fd3C85c05697b24743e580B03abCD6d0c65` |
| ModelBonding | `0x15f6c4bf4000747E0fDd85B33998A36F5BdF5007` |
| FeeDistributor (zETH) | `0x8Fb48F84AA69E89e0360e6d2D26C447AA57DcF73` |
| FeeDistributor (zBTC) | `0x403e8C79653B1cb7a5c0EaA313Ec0C7d0cAc7e2c` |
| FeeDistributor (zXRP) | `0xC69f8a8014b4d17ee2E7457109fF1DB33C0c7d7F` |
| FeeDistributor (zSOL) | `0xE990BFBc5c1e5779Cb54cB95150eDbBB2C2800d0` |
| Timelock | `0x1504cA3C050C88CcCa67696d642F634fc381fD03` |
| Zentroller | `0x24f9401284CE16CFe61e40C1F9e3fb37d15B878E` |
| ZentGovernor | `0x21ba1F7C028B1ADc78e75Ac187B08b1BDd567118` |
| HyperCoreAdapter | `0xfFc1Da47f780973e935Bb9F5a9d455aE7A5f7eac` |
| StrategyExecutor | `0x427c94150f3f700Dc2EDf7bCc97155A467E41F21` |

## Quick Deploy (Full Protocol)

```bash
# In zentory-protocol/contracts/
forge script script/DeployPipeline.s.sol \
  --rpc-url https://rpc.hyperliquid-testnet.xyz/evm \
  --private-key $PRIVATE_KEY \
  --broadcast --tc DeployPipeline
```

Required env vars: `PRIVATE_KEY`, `TREASURY`, `PROPOSER`, `KEEPER`, `GUARDIAN`,
`TEAM_WALLET_1..5`, `BACKER_WALLET_1..3`.

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
