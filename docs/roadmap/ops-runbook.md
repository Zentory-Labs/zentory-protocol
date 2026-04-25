# Ops runbook + launch gates

This is the minimal operational playbook for deploying and safely operating the Zentory Protocol.

## Environments

- **Local**: Foundry + local chain, unit/invariant tests, engine unit tests.
- **Testnet (HyperEVM testnet)**:
  - staged deployment (preview DApp + testnet contracts)
  - simulated keeper runs
- **Mainnet (HyperEVM)**:
  - immutable deployments
  - strict key separation

## CI (minimum)

### Protocol core (`ZentoryToken`)
- **Contracts**:
  - compile + unit tests
  - fuzz/invariant tests (separate job; allowed longer runtime)
  - static analysis: Slither (and lint if configured)
- **Engine**:
  - typecheck/lint + unit tests
  - TradeSignal digest parity fixture test

### DApp repo (`zentory-protocol-dapp-v2`)
- build + typecheck
- lint (make lint errors blocking before mainnet)
- basic route smoke tests

## Secrets and key management

### Keys
- **Deployer key**:
  - used only for deploying and initial wiring
  - should be retired after roles are transferred to governance/multisig
- **Signal signer key** (`authorizedSigner`):
  - lives in KMS/HSM if possible
  - rotatable; rotation documented and tested
- **Keeper execution key** (`KEEPER_ROLE`):
  - used only to call `executeSignal`
  - rate-limited and monitored
- **Guardian key**:
  - pause authority; ideally multisig

### Storage policy
- no secrets in `.env` committed to git
- production secrets stored in Vercel/hosting provider secrets + KMS

## Deployment steps (high level)

1. Deploy contracts (pipeline or phased scripts).
2. Verify:
   - timelock + governor roles
   - vault fee recipients set to FeeDistributors
   - vault staking gating set (if desired for stage)
   - StrategyExecutor authorized signer set
   - HyperCoreAdapter asset config locked to governor
3. Deploy DApp:
   - set RPC + contract addresses
   - set API endpoints for log-only vs execute
4. Run smoke checks:
   - deposits disabled/enabled as expected
   - signals log works
   - execute blocked without auth

## Monitoring (minimum viable)

- **On-chain**:
  - index `TradeSignalExecuted`, `SignalRejected`, `PausedSet`
  - index FeeDistributor events (`FeeAccumulated`, `FeesDistributed`)
  - alert on role changes (AccessControl events)
- **Off-chain/API**:
  - request logs for privileged endpoints
  - rate limit violations
  - audit log integrity (append-only)

## Incident response

### When to pause
- suspicious execute volume / unexpected trades
- signature verification anomaly
- unexpected adapter config mutation
- exploit reports / abnormal fund movements

### Actions
- guardian pauses `StrategyExecutor`
- risk council activates vault circuit breaker(s)
- revoke keeper role(s)
- rotate authorized signer (if compromise suspected)
- publish postmortem and update runbook

## Governance operations

- **Role ownership**:
  - timelock owns admin roles where possible
  - deployer renounces after setup
- **Change management**:
  - all parameter changes via proposals
  - emergency actions documented (guardian + risk council)

## Launch gates (Go / No-Go)

“Go” requires:
- all security-blocker acceptance criteria satisfied
- contract tests green (unit + invariant)
- digest parity test green
- DApp execute endpoints authz + rate limiting + audit logs proven
- monitoring/alerts configured
- rollback/response plan rehearsed on testnet

