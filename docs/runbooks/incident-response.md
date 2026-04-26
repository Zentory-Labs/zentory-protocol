# Incident Response Runbook (Testnet)

## Purpose

This runbook defines the fastest safe actions to take if Zentory Protocol behaves unexpectedly (unexpected trade execution, privileged key compromise, vault loss event, or governance misuse).

## Roles

- **Incident Commander (IC)**: owns decision-making and comms
- **Protocol Engineer**: contract/operator actions, on-chain verification
- **Security Engineer**: threat assessment, key rotation, forensic capture
- **Comms**: investor/community updates (if applicable)

## Severity

- **SEV0**: active loss / attacker action / keys compromised
- **SEV1**: severe bug with credible exploitation path
- **SEV2**: degraded functionality, no active exploit

## Immediate Actions (SEV0 / SEV1)

### 1) Freeze execution

- **Action**: Pause the `StrategyExecutor` (guardian/governor action).
- **Goal**: stop further trade execution immediately.
- **Verify**:
  - New `executeSignal` calls revert
  - `PausedSet`-type event emitted (or equivalent)

### 2) Freeze deposits (if vault incident)

- **Action**: Activate vault circuit breaker / pause deposits (if supported).
- **Goal**: prevent new deposits while incident is assessed.

### 3) Rotate keys (if compromise suspected)

- **Authorized signer**:
  - Queue governance action to `setAuthorizedSigner(newSigner)`
  - Verify old signer rejects immediately after execution
- **Keeper private key**:
  - Remove compromised key from any CI/secrets store
  - Replace `KEEPER_PRIVATE_KEY` on Vercel

### 4) Preserve evidence

- Capture:
  - tx hashes involved
  - block numbers
  - addresses / roles changes (`RoleGranted`/`RoleRevoked`)
  - relevant logs from `keeper_audit` (if configured)

## Investigation Checklist

- Confirm **what changed**:
  - recent governance proposals / timelock execution
  - role grants/revokes
  - signer changes
- Confirm **blast radius**:
  - which vaults affected
  - amounts moved
- Confirm **root cause**:
  - key compromise vs contract bug vs operator error

## Communications

- Internal: short, factual updates every 30–60 minutes for SEV0/SEV1
- External (if needed):
  - what happened
  - what was paused
  - what user funds are affected (if any)
  - next update time

## Recovery

- Patch and redeploy only after:
  - regression tests green
  - signer parity test green
  - invariant test suite green
  - Slither re-run with report captured

## Postmortem

- Timeline
- Root cause
- What worked / what didn’t
- Action items with owners + dates

