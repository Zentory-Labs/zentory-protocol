# Immunefi Bug Bounty Setup Guide

> Scope last reconciled 2026-06-04 against the actual `contracts/src/` tree and the
> canonical deployment list in [`DEPLOYMENTS.md`](../DEPLOYMENTS.md). Publish AFTER the
> external audit completes (audit-first is the norm) and AFTER mainnet deploy, so the
> in-scope assets table can be keyed to mainnet addresses.

## Step 1: Create Immunefi Account

1. Go to [https://immunefi.com](https://immunefi.com) and create a project
2. Verify ownership of the repository via GitHub integration
3. Add your smart contracts (list in scope below)

## Step 2: Configure Rewards

| Severity | Reward |
|----------|--------|
| Critical | Up to $25,000 USDC |
| High     | Up to $10,000 USDC |
| Medium   | Up to $3,000 USDC |
| Low      | Up to $500 USDC |

Most projects start at the lower end and increase after the first audit passes with no critical findings.

## Step 3: Add Your Contracts

- **Source code URL pattern:** `https://github.com/Zentory-Labs/zentory-protocol/blob/<audited-commit>/contracts/src/<path>.sol`
- **Deployment addresses:** testnet (HyperEVM 998) addresses are in [`DEPLOYMENTS.md`](../DEPLOYMENTS.md) — do NOT duplicate them here (single source of truth). Replace with mainnet addresses once M12 deploys.
- **Chain:** HyperEVM testnet = Chain ID **998**; mainnet Chain ID to be confirmed at M12.

### In-Scope Contracts (mainnet-deployed, value-bearing)

Reconciled to the real `contracts/src/` set (see `docs/AUDIT_READINESS.md §1` for the same list the auditors use):

**Token & treasury**
- `ZENT.sol` — fixed-supply ERC-20
- `ZENTStaking.sol` — veZENT staking / slashing
- `ZENTVesting.sol` — team/strategic/treasury vesting
- `ZENTBuyback.sol` — buyback-and-burn
- `ProtocolTreasury.sol` — protocol treasury
- `fees/FeeDistributor.sol` — performance-fee routing (per vault)

**Vaults (ERC-4626)**
- `vaults/BaseVault.sol` — shared vault logic
- `vaults/zBTCVault.sol`, `vaults/zETHVault.sol`, `vaults/zSOLVault.sol`, `vaults/zXRPVault.sol`

**Signal Arena**
- `signals/SignalRegistry.sol` — EIP-712 signal submission
- `signals/EpochScoring.sol` — epoch settlement / scoring / payout
- `signals/SubscriptionVault.sol` — signal subscriptions
- `staking/ModelBonding.sol` — model bonding / slashing

**Execution & keeper**
- `keeper/StrategyExecutor.sol`, `keeper/HyperCoreAdapter.sol`

**Governance**
- `governance/Timelock.sol`, `governance/Zentroller.sol`, `governance/ZentGovernor.sol`

**Airdrop**
- `airdrop/MerkleDistributor.sol` — claim contract

### Out-of-Scope

- **Shadow stack (testnet-only):** `shadow/ShadowPriceOracle.sol`, `shadow/ShadowSpotAdapter.sol`, `shadow/ShadowUSDC.sol`, and `vaults/SpotVault.sol` — these are the testnet research/shadow harness, never deployed to mainnet.
- **Interfaces & libraries** (`interfaces/*.sol`, `signals/SignalTypes.sol`, `vaults/IVault.sol`) — no executable state.
- Mock/faucet test tokens (testnet only).
- Frontend / dApp bugs, social engineering, DDoS, and bugs in third-party dependencies (OpenZeppelin, etc.).

## Step 4: Publish & Promote

- Publish the program on Immunefi.
- The bug-bounty page is live at **https://app.zentorylabs.com/bug-bounty** (already linked from the dApp footer).
- Announce on Discord (#security) and X.

## Step 5: Triage Process

1. Security team acknowledges within **24 hours**
2. Severity assessed within **7 days**
3. Fix deployed + reward within **30 days** for critical bugs

## Budget Recommendation

Set aside **$50,000–$100,000** for year-1 payouts. Critical DeFi bugs can cost $10M+ (Euler Finance 2023: $197M); a proactive bounty is far cheaper than incident response.

## Quick Links

- Immunefi: https://immunefi.com
- ZENTORY Bug Bounty Page: https://app.zentorylabs.com/bug-bounty
- Security Contact: security@zentorylabs.com
- GitHub Repo: https://github.com/Zentory-Labs/zentory-protocol
- Canonical deployment addresses: [`DEPLOYMENTS.md`](../DEPLOYMENTS.md)
