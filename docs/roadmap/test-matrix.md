# Test & verification matrix (launch gates)

This is the “evidence before launch” matrix for contracts + engine + DApp/API.

## Contracts (local + fork)

### Keeper auth + replay
- **Scenario**: valid signal executes once.
  - **Gate**: passes unit test; emits `TradeSignalExecuted`.
- **Scenario**: invalid signer.
  - **Gate**: reverts with `InvalidSignature`.
- **Scenario**: replay nonce.
  - **Gate**: reverts; nonce monotonicity holds per vault.
- **Scenario**: expiry in past.
  - **Gate**: reverts.

### Governance timelock
- **Scenario**: proposal queues and executes through timelock.
  - **Gate**: governor state transitions prove queue + delay enforcement.
  - **Evidence**: test that time-travels through delay and calls succeed only after.

### Fee routing
- **Scenario**: vault accrues fees; `claimFees()` routes into FeeDistributor.
  - **Gate**: distributor pulls underlying via `transferFrom` and increases `pendingFees[vault]`.
- **Scenario**: `distribute(vault)` splits to gp/insurance/treasury.
  - **Gate**: balances change as expected; buyback pool accounting is correct.

### Vault access gating
- **Scenario**: after `setStaking`, non-staker deposit/mint fails.
  - **Gate**: revert.
- **Scenario**: staker deposit/mint succeeds.
  - **Gate**: shares minted; invariant `totalAssets()` correct.

### ERC-4626 accounting + invariants (must-have before TVL)
- **Scenario**: random deposits/withdraws around fee accrual.
  - **Gate**: no share inflation; `totalAssets()` never negative; fee accrual bounded.
- **Evidence**: fuzz + invariants (Foundry invariant tests).

## Engine (unit + integration)

### TradeSignal digest parity
- **Scenario**: Python signer digest matches Solidity verifier exactly.
  - **Gate**: fixture test signs a signal and Solidity accepts it.
  - **Evidence**: deterministic test vectors (hardcoded signal + expected digest + signature).

### Manual mode separation
- **Scenario**: “log-only” pathway never touches a private key.
  - **Gate**: code audit + unit tests that log-only endpoints do not call signer.

### Lumibot backtesting correctness
- **Scenario**: known price series yields known trades.
  - **Gate**: regression test matches expected outputs.
  - **Evidence**: committed fixtures + reproducible report artifact.

## DApp / API (security + UX)

### Privileged endpoints
- **Scenario**: execute requires authn + role.
  - **Gate**: unauthorized → 401/403, authorized → 200, audit log written.
- **Scenario**: rate limiting on execute.
  - **Gate**: bursts are throttled; errors are safe and do not leak secrets.

### Wallet UX + chain correctness
- **Scenario**: wrong chain (not HyperEVM) shows blocking UI state.
  - **Gate**: no “execute” CTA works off-chain; user sees fix instructions.

### Smoke tests (per route)
- **Scenario**: `/`, `/stake`, `/govern`, `/signals`, `/admin`.
  - **Gate**: no runtime errors; loading/error states render correctly.

## “Ready for mainnet” minimum bar

All of the following must be true:
- Contract suite passes unit + invariant tests.
- Signal digest parity test passes.
- Timelock lifecycle test passes.
- Execute endpoints are authz-gated + rate limited + audited.
- A runbook exists (deploy, pause, rotate keys, incident response).

