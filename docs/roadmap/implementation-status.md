# Implementation Status (vs original plan)

This document maps the original build plan (`docs/plans/2026-04-24-001-feat-zent-protocol-build-plan.md`) and the execution pivot (`goal.md`) to what currently exists in the repos.

## Repos in play

- **Protocol core (contracts + engine)**: `C:\Users\juan\OneDrive\Documents\GitHub\ZentoryToken`
- **DApp (deployed to app.zentorylabs.com)**: `C:\Users\juan\OneDrive\Documents\GitHub\zentory-protocol-dapp-v2`
- **Marketing**: `C:\Users\juan\OneDrive\Documents\GitHub\zentorylabs.com`

Legend: **Done** / **Partial** / **Missing**. “Partial” means the thing exists but is not correct or not safely end-to-end.

## U1 — Scaffold monorepo & infra

- **Done**: `contracts/`, `engine/`, `frontend/` exist in `ZentoryToken`.
- **Partial**: CI is present for contracts (`contracts/.github/workflows/test.yml`), but frontend/engine CI is not clearly standardized.

## U2 — ZENT ERC-20 token

- **Partial**
  - **Exists**: `contracts/src/ZENT.sol`, `contracts/test/ZENT.t.sol`
  - **Notable mismatch**: `mintForTestnet` exists (chain-gated) → keep tightly scoped and ensure it can’t be enabled in production.

## U3 — BaseVault ERC-4626 + HWM fees + rails

- **Partial**
  - **Exists**: `contracts/src/vaults/BaseVault.sol`, `zETHVault.sol`, `zBTCVault.sol`, `zSOLVault.sol`, `zXRPVault.sol`
  - **Missing vs plan**:
    - “Alpha above HODL baseline” accounting (currently HWM-only).
    - Staking-gated deposits (vault entrypoints don’t enforce access yet).
    - Circuit breaker drawdown policy (threshold exists but isn’t automatically enforced).

## U4 — Staking + ModelBonding

- **Partial**
  - **Exists**: `contracts/src/staking/ZENTStaking.sol`, `contracts/src/staking/ModelBonding.sol`
  - **Missing vs plan**:
    - Vault-side enforcement of `hasAccess` / `minStake` on deposit/mint.

## U5 — FeeDistributor (routing + buyback/burn)

- **Partial**
  - **Exists**: `contracts/src/fees/FeeDistributor.sol`
  - **Missing vs plan**:
    - End-to-end wiring (vault fee accrual → distributor accumulate/distribute) is not proven correct.
    - Real buyback swap is stubbed (burns any ZENT already held).
  - **Doc mismatch**: `contracts/DEPLOYMENT.md` fee split differs from plan and code and must be reconciled.

## U6 — Governance (Governor + Timelock + risk council)

- **Partial**
  - **Exists**: `contracts/src/governance/ZentGovernor.sol`, `Timelock.sol`, `Zentroller.sol`
  - **High-risk mismatch**:
    - “Execute through timelock” is not implemented as expected (no `GovernorTimelockControl`-style linkage).
    - Risk council pause/unpause described in docs doesn’t match `Zentroller.sol` implementation.

## U7 — Keeper / StrategyExecutor

- **Partial (high risk)**
  - **Exists**: `contracts/src/keeper/StrategyExecutor.sol`, `HyperCoreAdapter.sol`
  - **High-risk mismatch**:
    - Signature auth is not bound to an authorized signer (accepts any nonzero recovered address).
    - `HyperCoreAdapter.setAssetConfig` access control needs review.
    - Leverage checks / vault→asset mapping are placeholders.

## U8 — Engine (GP + strategy + signals)

Pivot in `goal.md`: manual execution now; Lumibot for backtesting; GP compute later.

- **Partial**
  - **Exists**:
    - GP primitives: `engine/src/genetic_programming/*`
    - Strategy logic: `engine/src/strategy/*`
    - Signals abstractions: `engine/src/signals/*`
    - Execution clients: `engine/src/execution/*`
  - **Missing vs plan**:
    - Real price series provider for strategies.
    - On-chain per-vault nonce fetch and replay parity.
    - Canonical single “TradeSignal” spec + signature parity proven vs Solidity.
    - Lumibot provider integration is stubbed.

## U9 — Deployment scripts

- **Partial**
  - **Exists**: `contracts/script/Deploy*.s.sol`, `DeployPipeline.s.sol`, plus broadcast artifacts.
  - **Missing/mismatched**:
    - Script parameter correctness (underlying assets, distributor asset args) needs hard verification.
    - Canonical `deployments.json` artifact referenced in docs is not present/standardized.

## U10 — Frontend dashboard

- **Partial**
  - **Deployed DApp** is in `zentory-protocol-dapp-v2` and contains:
    - vault overview
    - staking
    - governance (limited)
    - signals log/execute
    - admin panel
  - **Missing** (product-level):
    - vault detail pages, deposit/withdraw flows, user positions
    - governance proposal discovery/creation flows
    - robust privilege gating for execute/admin actions

## U11 — Audit readiness

- **Missing / not yet at audit-ready bar**
  - No dedicated audit report doc.
  - No invariant testing suite surfaced.
  - Several correctness blockers (keeper signature auth, timelock wiring, fee wiring) must be fixed first.

## U12 — Mainnet deployment

- **Missing**
  - Blocked on: U11 gates + contract correctness + ops runbooks + monitoring + incident response.

