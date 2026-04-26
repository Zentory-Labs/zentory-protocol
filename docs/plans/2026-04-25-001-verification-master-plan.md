# Zentory Protocol — Verification Master Plan

## Overview

Comprehensive end-to-end verification of the Zentory Protocol before mainnet/token launch, covering smart contracts (Foundry), execution engine (Python), DApp (Next.js + wagmi), and operational security. Every finding must have a concrete test, evidence artifact, and a Go/No-Go gate.

---

## Current State Summary

### What exists

**Contracts** (`ZentoryToken/contracts/`):
- ZENT ERC-20 + Vesting
- BaseVault ERC-4626 (zETH, zBTC, zXRP, zSOL) — performance fee, circuit breaker, trade log
- ZENTStaking — lock/stake, veBalance, hasAccess
- ModelBonding — unbond cooldown
- FeeDistributor — accumulates from vault, distributes to gp/insurance/treasury/buyback
- ZentGovernor — vote-escrowed voting via veBalance
- Timelock — 48h delay controller
- Zentroller — staking link
- StrategyExecutor — ECDSA-signed trade execution, nonce replay protection, authorized signer
- HyperCoreAdapter — CoreWriter precompile adapter for HyperCore

**Engine** (`ZentoryToken/engine/`):
- GP primitives, strategy components, signals abstractions
- `signer.py` — EIP-712 signing (updated to match new Solidity digest)

**DApp** (`zentory-protocol-dapp-v2`):
- Vault overview page
- Stake page (approve → stake flow, voting power display)
- Govern page (proposals, voting)
- Signals page (log trade + execute via keeper)
- Admin page (risk controls)
- Shared glass/blue-steel theme applied

### Recent contract changes (not yet deployed)

| File | Change |
|------|--------|
| `StrategyExecutor.sol` | Added `authorizedSigner`, proper EIP-712 digest with `\x19\x01` prefix + price in struct; added `SIGNAL_TYPEHASH`, `vaultRegistry`, `setAuthorizedSigner`, `setVaultRegistry`; added GOVERNOR_ROLE to constructor grants |
| `HyperCoreAdapter.sol` | Added AccessControl, GOVERNOR_ROLE, constructor takes `governor_`, `setAssetConfig` gated to GOVERNOR_ROLE |
| `ZentGovernor.sol` | Now inherits GovernorTimelockControl; queues/executes via Timelock |
| `BaseVault.sol` | Added `staking` (mutable), `setStaking()`, `setFeeRecipient()`; `deposit`/`mint` check staking.hasAccess; `claimFees` routes to FeeDistributor if recipient is contract |
| `zETH/BTC/XRP/SOL Vault` | No constructor changes (staking set post-deploy via `setStaking`) |
| `DeployStaking.s.sol` | FeeDistributor now receives `IERC4626(vault).asset()` |
| `DeployPipeline.s.sol` | Wires staking, fee recipients, authorized signer, vault registry |
| `signer.py` | Added `price` to digest, `\x19\x01` prefix, correct SIGNAL typehash |
| `BaseVault.t.sol` | Tests updated to cover staking gating, fee routing |
| `StrategyExecutor.t.sol` | Tests updated for authorized signer, proper EIP-712 digest |

### Security assumptions (what must be proven by tests)

1. `StrategyExecutor.executeSignal` rejects any signature not from `authorizedSigner`
2. Signal digest includes chain ID + executor address (cross-chain replay impossible)
3. Nonces are strictly monotonic per vault
4. HyperCoreAdapter config mutations require GOVERNOR_ROLE
5. Governor proposals queue through Timelock before execution
6. Vault deposits/mints require active staking position once staking is set
7. Fee routing: vault claimFees → FeeDistributor.accumulate → distribute splits correctly
8. Python signer digest matches Solidity verifier (digest parity fixture)

---

## Scope Boundaries

### In scope
- All contracts in `contracts/src/`
- All engine sign/verify paths (`engine/src/signals/`)
- All DApp pages and API routes (`frontend/app/`, `frontend/app/api/`)
- Privileged keeper execute endpoints
- Wallet connection and chain validation flows

### Out of scope (deferred)
- Frontend design/branding (already addressed)
- Lumibot backtesting harness (documented in execution-pivot.md)
- Third-party audit (separate engagement)

---

## Threat Model

### Trust boundaries

| Component | Trust assumption |
|-----------|----------------|
| ZENT token | No mint after deployment; fixed 1B supply |
| Vault contracts | Only keeper (KEEPER_ROLE) can record trades; only vault admin can set fee recipient/staking |
| ZENTStaking | Only governor can change minStake; one position per address; no early withdrawal |
| StrategyExecutor | Only KEEPER_ROLE can submit signals; only authorized signer signatures pass |
| HyperCoreAdapter | Only GOVERNOR_ROLE can change asset config |
| FeeDistributor | Only GOVERNOR_ROLE can trigger buyback or withdraw gp/treasury pools |
| Timelock | 48h delay before any governance execution |
| DApp frontend | User must confirm wallet transactions; frontend never holds private keys |

### Known high-value targets

1. **Authorized signer key** — compromise lets attacker submit fake signals
2. **Keeper execution key** — compromise lets attacker call executeSignal repeatedly
3. **Vault access gating bypass** — non-staker deposits into vaults
4. **Fee redirect** — attacker changes feeRecipient to drain accrued fees
5. **Replay of valid signal** — same nonce used twice drains vault
6. **Cross-chain replay** — signal from testnet used on mainnet

---

## Verification Units

### V1 — Contract Unit Tests (Foundry)

**V1.1 Access Control — StrategyExecutor**
- Unauthorized caller cannot execute signal → reverts
- Attacker with valid signature but wrong signer → reverts
- Guardian can pause; unpausing requires guardian or admin
- Governor can update authorized signer; previous signer rejected after update
- Non-governor cannot call setAuthorizedSigner / setVaultRegistry

**V1.2 Signature Verification — StrategyExecutor**
- Valid signature from authorized signer passes
- Signature with wrong v/r/s values → reverts InvalidSignature
- Signature with tampered vault/direction/size/price/nonce/expiry → reverts
- Signature without `\x19\x01` prefix (old format) → reverts
- Signature digest mismatches DOMAIN_SEPARATOR → reverts
- Same signal replayed → reverts NonceAlreadyUsed

**V1.3 Nonce Replay Protection**
- Nonce 1 executes; nonce 1 again → reverts
- Nonce 2 after nonce 1 → succeeds
- Nonce 0 after nonce 1 → reverts

**V1.4 HyperCoreAdapter Access Control**
- Non-governor calling setAssetConfig → reverts
- Governor calling setAssetConfig → succeeds
- Non-gov calling sendLimitOrder with unsupported asset → reverts

**V1.5 Vault ERC-4626 Correctness**
- Deposit/mint without staking set → succeeds (bootstrap mode)
- After setStaking: deposit from non-staker → reverts
- After setStaking: deposit from staker → succeeds
- ClaimFees when feeRecipient is EOA → direct transfer
- ClaimFees when feeRecipient is FeeDistributor → accumulate called
- Performance fee only charged on alpha above HWM

**V1.6 Fee Routing End-to-End**
- evaluateFees → claimFees → FeeDistributor.accumulate → pendingFees increases
- distribute() → gp/insurance/treasury receive correct percentages
- Buyback pool accumulates correctly

**V1.7 Governance Timelock**
- Proposal created → voting delay passes → vote succeeds → queue → timelock delay passes → execute
- Non-proposer cannot queue; proposer can
- Timelock admin can grant/revoke roles

**V1.8 Staking**
- Stake 100 ZENT for 30 days → position created, lockEnd correct
- Extend lock to longer duration → succeeds
- Extend lock to shorter → reverts
- Withdraw before expiry → reverts
- Withdraw after expiry → succeeds
- hasAccess true when staked >= minStake and lock not expired
- hasAccess false when lock expired (even with balance)

**V1.9 Invariant Tests (ERC-4626)**
- Invariant: totalAssets never underflows
- Invariant: convertToShares(convertToAssets(shares)) == shares (within 1 unit rounding)
- Invariant: totalSupply > 0 implies totalAssets > 0
- Invariant: performanceFeeAccrued <= totalAssets
- Invariant: after any deposit/withdraw, vault share price >= 1 (no inflation exploit)

### V2 — Digest Parity Tests (Cross-language)

**V2.1 Python Signer vs Solidity Verifier**
- Deterministic test vector: known (vault, direction, size, price, nonce, expiry, chainId, executor)
- Sign with Python signer.py → produce signature
- Submit to Solidity StrategyExecutor → passes
- Verify digest computed in Python exactly matches Solidity DOMAIN_SEPARATOR approach
- Test both valid and invalid signatures

### V3 — DApp / Frontend Security Tests

**V3.1 Wallet Connection**
- Connected on wrong chain → shows blocking UI, no execute buttons work
- Disconnected → shows "connect wallet" state on all pages
- Switch to HyperEVM testnet → full functionality restored

**V3.2 Stake Flow**
- Approve ZENT → allowance granted
- Stake 100 ZENT → voting power updates without refresh after tx confirm
- Error: stake > balance → clear error message, no revert
- Error: stake < minStake → reverts on-chain with descriptive message
- Error: lockDuration < 7 days → reverts on-chain

**V3.3 Signals Execute Flow (Keeper)**
- Non-keeper calling recordTradeManual → reverts AccessControl
- Keeper calling recordTradeManual → succeeds, event emitted
- Execute signal without KEEPER_ROLE → reverts
- Execute signal with valid signature + KEEPER_ROLE → succeeds

**V3.4 Privileged API Endpoints**
- Execute endpoint without auth → 401/403
- Execute endpoint with valid auth → 200 + event indexed
- Rate limit exceeded → 429 with retry-after header
- Invalid signal parameters → 400 with validation error

**V3.5 Governance**
- Vote without voting power → tx submits but has no effect (governor handles)
- Vote with voting power → succeeds, vote weight recorded
- Proposal state transitions correctly: Pending → Active → Succeeded → Queued → Executed

### V4 — Penetration Testing (Manual)

**P4.1 Authorized Signer Compromise Scenario**
- Attacker obtains authorized signer private key
- Tries to submit signal with max size on all vaults
- Expected: reverts if signer not in KEEPER_ROLE; if KEEPER_ROLE also compromised → catastrophic, document as critical finding

**P4.2 Front-Running Trade Signal**
- Attacker observes pending signal in mempool
- Front-runs with same nonce but different price → expected: nonce prevents replay; different nonce → signal executes first

**P4.3 Timelock Bypass**
- Governance proposal schedules critical action
- Attacker tries to execute before timelock delay → expected: reverts

**P4.4 Flash-Loan Governance Attack**
- Attacker acquires massive ZENT, stakes, votes in proposal, withdraws
- Must pass quorum + vote succeeds → document as risk; mitigation is vote-escrowed (veZENT decay limits short-term acquisition)

**P4.5 Keeper Key Theft**
- Attacker steals keeper private key
- Can call executeSignal (if signer also compromised) or recordTradeManual
- Guardian can pause → test: guardian pause stops all execution immediately

**P4.6 Vault Circuit Breaker Bypass**
- Attacker tries to deposit during circuit breaker activation
- Expected: reverts with CircuitBreakerActive

**P4.7 Fee Recipient Hijack**
- Attacker tries to change feeRecipient via governance → requires proposal
- Non-governor trying direct change → reverts AccessControl

### V5 — Operational Verification

**V5.1 Deployment Verification**
- Deploy pipeline runs without error on testnet
- All contract addresses written to deployments.json
- Roles correctly assigned: governor is admin of all contracts post-deployment
- Timelock admin transferred to multisig

**V5.2 Monitoring Setup**
- Events indexed: TradeSignalExecuted, SignalRejected, PausedSet, FeeAccumulated, FeesDistributed, RoleGranted, RoleRevoked
- Alert triggers: any PausedSet event, >5 SignalRejected in 1 hour, unusual role grants

**V5.3 Incident Response Runbook Test**
- Scenario: unexpected trade on vault
- Runbook steps: pause executor → pause vault → investigate → publish postmortem
- Verify: all steps executable without code changes

**V5.4 Key Rotation Test**
- Authorized signer key rotation: call setAuthorizedSigner(newKey) via governance
- Old key rejected after rotation

**V5.5 Network Confusion Test**
- User on Ethereum mainnet → DApp blocks all interactions with clear message
- User switches to HyperEVM → functionality restored

---

## Go / No-Go Gates

| Gate | Criteria | Evidence |
|------|----------|----------|
| G1 | All V1 unit tests pass (Foundry) | `forge test` green output |
| G2 | Invariant tests pass with no failing invariants | `forge test --match-invariant` output |
| G3 | Slither finds no HIGH/CRITICAL issues (except suppressed) | Slither JSON report |
| G4 | Digest parity test (V2) passes | Fixture test output |
| G5 | DApp smoke tests pass on testnet | Playwright/Cypress test output |
| G6 | Privileged API auth + rate limiting verified | HTTP test output |
| G7 | P4 pentest findings: 0 CRITICAL, ≤2 HIGH | Pentest report |
| G8 | Governance timelock lifecycle test passes | Foundry test with time warp |
| G9 | Monitoring alerts fire correctly on test events | Alert delivery screenshot |
| G10 | Runbook tested end-to-end on testnet | Executed runbook with timestamp |

**All 10 gates must pass before any mainnet deployment or token launch consideration.**

---

## Test Artifacts Required

| Artifact | Tool | Location |
|----------|------|----------|
| Unit test results | `forge test -vv` | CI output |
| Invariant test results | `forge test --match-invariant -vv` | CI output |
| Slither report | `slither .` | `reports/slither.json` |
| Digest parity fixture | Python test | `engine/tests/test_digest_parity.py` |
| DApp smoke tests | Playwright | `zentory-protocol-dapp-v2/tests/` |
| API security tests | HTTP tests (httpx/pytest) | `engine/tests/test_api_security.py` |
| Pentest report | Manual + automated | `docs/reports/pentest-YYYY-MM-DD.md` |
| Coverage report | `forge coverage` | `reports/coverage.txt` |

---

## Files Modified (by this plan)

### Contracts
- `contracts/test/keeper/StrategyExecutor.t.sol` — add authorized signer tests, EIP-712 digest tests
- `contracts/test/vaults/BaseVault.t.sol` — add staking gating tests, fee routing tests
- `contracts/test/staking/ZENTStaking.t.sol` — add invariant tests for veBalance
- `contracts/test/governance/ZentGovernor.t.sol` — add timelock lifecycle test
- `contracts/test/fees/FeeDistributor.t.sol` — add distribute + buyback tests

### Engine
- `engine/tests/test_digest_parity.py` — deterministic fixture test
- `engine/tests/test_api_security.py` — auth + rate limiting tests

### DApp
- `frontend/tests/smoke.spec.ts` — Playwright smoke tests
- `frontend/tests/security.spec.ts` — auth/chain validation tests

### Docs
- `docs/reports/slither-YYYY-MM-DD.json` — Slither output
- `docs/reports/pentest-YYYY-MM-DD.md` — Pentest report
- `docs/runbooks/incident-response.md` — Incident response runbook
