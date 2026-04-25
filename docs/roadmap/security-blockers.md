# Security blockers — fixes + acceptance criteria

This is the concrete “blockers” checklist the protocol must satisfy before any meaningful TVL / automation.

## 1) Keeper signature authorization (StrategyExecutor)

### Fix implemented
- `StrategyExecutor` now requires signatures to recover **exactly** `authorizedSigner`.
- Digest is EIP-712 style: \(keccak256("\x19\x01" || DOMAIN_SEPARATOR || structHash)\).
- Signal struct binds **vault + direction + size + price + nonce + expiry**.
- `authorizedSigner` is set via `setAuthorizedSigner()` by an admin/governor.

### Acceptance criteria
- Unauthorized signatures always revert.
- A signature for \((vault A)\) cannot be replayed on \((vault B)\).
- A signature cannot be replayed cross-chain (DOMAIN includes chain id).
- A signature cannot be replayed with modified `price` or `size`.

### Tests (required)
- Unit test: valid signature passes; invalid signer fails.
- Unit test: changing any of {vault, direction, size, price, nonce, expiry} breaks verification.
- Unit test: replay with same nonce fails.

## 2) Replay protection (per-vault nonces)

### Fix implemented
- `StrategyExecutor` enforces strictly increasing `nonces[vault]`.

### Acceptance criteria
- Same (vault, nonce) cannot be executed twice.
- Lower nonce always reverts.

### Tests (required)
- Execute nonce \(n\) then execute nonce \(n\) again → revert.
- Execute nonce \(n\) then execute nonce \(n-1\) → revert.

## 3) HyperCoreAdapter config access control

### Fix implemented
- `HyperCoreAdapter` now uses `AccessControl`.
- `setAssetConfig()` is restricted to `GOVERNOR_ROLE`.

### Acceptance criteria
- Random EOA cannot mutate asset config.
- Governor can rotate indices/decimals safely.

### Tests (required)
- `setAssetConfig()` from non-governor reverts.
- `setAssetConfig()` from governor succeeds.

## 4) Governance timelock execution wiring

### Fix implemented
- `ZentGovernor` now inherits `GovernorTimelockControl` and queues/executes via the timelock.

### Acceptance criteria
- A passed proposal enters “Queued” state before execution.
- Execution is only possible after the timelock delay.

### Tests (required)
- Proposal lifecycle test: propose → vote → queue → execute (time travel).

## 5) Fee routing wiring (vault → FeeDistributor)

### Fix implemented
- Vault fee claims now route via `IFeeDistributor.accumulate()` when `feeRecipient` is a contract.
- Vault now supports updating `feeRecipient` via `setFeeRecipient()` (admin-only) to point at the correct distributor per asset.
- Deploy scripts updated so `FeeDistributor(asset=underlying)` is correct, and pipeline wires each vault’s `feeRecipient` to its corresponding distributor.

### Acceptance criteria
- `BaseVault.claimFees()` increases `FeeDistributor.pendingFees(vault)` and transfers underlying from the vault to the distributor.
- `FeeDistributor.distribute(vault)` splits and transfers the non-buyback allocations.

### Tests (required)
- Fee accrual + claim routes into distributor.
- Distribute sends to gp/insurance/treasury and accounts buyback pool.

## 6) Vault access policy (stake-gated deposits)

### Fix implemented
- Vaults support stake gating via `setStaking()` (admin-only, one-time).
- When staking is set, `deposit()` and `mint()` require `staking.hasAccess(receiver)`.

### Acceptance criteria
- Before staking is set: deposits work (testnet / bootstrap mode).
- After staking is set: deposits/mints without access revert; with access succeed.

### Tests (required)
- Deposit before staking set succeeds.
- After `setStaking()`: deposit for user without stake reverts.
- After `setStaking()`: deposit for staker succeeds.

