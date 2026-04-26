# Monitoring Setup Guide — G9 / G10 Evidence

This guide walks through wiring on-chain monitoring (G9) and testing the incident runbook (G10).

---

## Step 1 — Choose a Monitoring Provider

**Option A: Tenderly (recommended for speed)**

1. Sign up at https://tenderly.co (free tier available)
2. Click **Add Project** → name it `Zentory Protocol`
3. Add contract addresses after deployment:
   - `StrategyExecutor`
   - Each `BaseVault` instance
   - `ZentGovernor`
   - `Timelock`

4. Under **Contracts → Alerts**, create alerts:

| Alert Name | Trigger | Action |
|---|---|---|
| `A1-PausedSet` | `PausedSet` event on StrategyExecutor | Email + PagerDuty |
| `A2-RoleChange` | `RoleGranted` or `RoleRevoked` on any contract | Email + PagerDuty |
| `A3-SignalRejected` | `SignalRejected` event, >5 in 1 hour | Discord webhook |

5. Save the **Alert ID** (shown in URL after creation) — you'll reference it in evidence.

**Option B: OpenZeppelin Defender**

1. Sign up at https://defender.openzeppelin.com (free tier available)
2. Create a **Relayer** (autonomous agent with private key for sending txs)
3. Add contracts via **Contracts → Add Contract**
4. Create **Sentinals** (event monitors):

| Sentinel | Event | Action |
|---|---|---|
| `S1-Pause` | `PausedSet(bool)` on StrategyExecutor | Email |
| `S2-Roles` | `RoleGranted`/`RoleRevoked` on AccessControl | Email |
| `S3-Rejected` | `SignalRejected` on StrategyExecutor | Webhook |

---

## Step 2 — Configure Alert Routing

For each alert, set one or more destinations:

| Destination | Use Case |
|---|---|
| Email (ops@zentory.io) | A1 critical alerts |
| PagerDuty / OpsGenie | A1/A2 after-hours escalation |
| Discord webhook (`#alerts` channel) | A3/A4 noisy/debug alerts |
| Slack webhook (`#security-ops`) | Alternative to Discord |

---

## Step 3 — Collect G9 Evidence (Alert Firing Proof)

G9 requires proof that alerts fire when events occur. Do this on **testnet**:

### 3a. Trigger a Test Pause

```bash
# In the contracts/ directory
forge script script/DeployPipeline.s.sol \
  --rpc-url $HYPEREVM_TESTNET_RPC \
  --private-key $TEST_DEPLOYER_KEY \
  --broadcast -vvv

# Then pause via the guardian key
cast send <STRATEGY_EXECUTOR_ADDRESS> \
  "setPaused(bool)" true \
  --rpc-url $HYPEREVM_TESTNET_RPC \
  --private-key $GUARDIAN_KEY
```

### 3b. Capture Alert Evidence

1. **Screenshot the alert email or Slack/Discord notification** arriving within 5 minutes.
2. Note the **triggering transaction hash** and **block timestamp**.
3. Save as `docs/reports/g9-alert-evidence-YYYY-MM-DD.png` (or `.pdf`).

### 3c. Unpause to Reset

```bash
cast send <STRATEGY_EXECUTOR_ADDRESS> \
  "setPaused(bool)" false \
  --rpc-url $HYPEREVM_TESTNET_RPC \
  --private-key $GUARDIAN_KEY
```

---

## Step 4 — Collect G10 Evidence (Runbook Test)

G10 requires a controlled end-to-end test of the incident runbook. Execute on **testnet**.

### Prerequisites

- Monitoring wired (from Step 1–2)
- Incident runbook reviewed (`docs/runbooks/incident-response.md`)
- Testnet deployer key with `GUARDIAN_ROLE` on StrategyExecutor

### Test Procedure

| Step | Action | Expected Result |
|---|---|---|
| 1 | Simulate alert condition: pause StrategyExecutor | Alert fires within 5 min |
| 2 | On-call receives page/email | Alert acknowledged in PagerDuty |
| 3 | IC reviews alert, checks Tenderly/Defender dashboard | Tx hash + event visible |
| 4 | IC determines it's a controlled test | No real incident opened |
| 5 | Unpause contract | System returns to normal |
| 6 | Document evidence | Save tx hash + timestamp + screenshot |

### Evidence to Collect

Save all of the following to `docs/reports/g10-runbook-test-YYYY-MM-DD/`:
- Screenshot of alert delivery (email, Slack, PagerDuty)
- Transaction hash of the pause tx
- Transaction hash of the unpause tx
- Block timestamps for both
- Tenderly/Defender event log screenshot showing `PausedSet` event
- Notes on response time (alert latency)

---

## Step 5 — Update Implementation Status

After completing the above, update `docs/runbooks/monitoring-plan.md`:

```markdown
| Component | Status | Notes |
|---|---|---|
| On-chain event indexing | **WIRED** | Tenderly project added |
| Alert routing (A1–A4) | **WIRED** | PagerDuty + Discord configured |
| API rate-limit alerting | **WIRED** | Vercel Analytics + log aggregation |
| Monitoring dashboard | **WIRED** | Tenderly dashboard: https://... |
| G9 evidence (alert test) | **DONE** | `docs/reports/g9-alert-evidence-2026-04-XX.png` |
| G10 evidence (runbook tested) | **DONE** | `docs/reports/g10-runbook-test-2026-04-XX/` |
```

---

## Quick-Reference: Contract Events to Monitor

| Contract | Event | Severity |
|---|---|---|
| `StrategyExecutor` | `PausedSet(bool paused)` | **Critical (A1)** |
| `StrategyExecutor` | `SignalRejected` | **Medium (A3)** |
| `StrategyExecutor` | `RoleGranted`/`RoleRevoked` | **Critical (A2)** |
| `BaseVault` | `CircuitBreakerActivated` | **High** |
| `BaseVault` | `CircuitBreakerAutoTriggered` | **High** |
| `BaseVault` | `TradeExecuted` | **Info** |
| `BaseVault` | `PerformanceFeeAccrued` | **Info** |
| `ZentGovernor` | `ProposalCreated` | **Info** |
| `ZentGovernor` | `VoteCast` | **Info** |
