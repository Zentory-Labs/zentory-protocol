# G10 Evidence — Incident Response Runbook Test
Date: 2026-04-27
Tool: OpenZeppelin Defender (Tenderly does not support HyperEVM)

## Runbook Tested

Reference: `docs/runbooks/incident-response.md`

## Controlled Test Execution

This test was executed on **HyperEVM Testnet** (chain 998) against the live deployment.

### Test: Guardian Pause Response

| Step | Action | Result |
|------|--------|--------|
| 1 | Trigger alert: call setPaused(true) on StrategyExecutor | PASS - Tx 0x89d821... succeeded |
| 2 | On-call receives page/email (Defender Sentinel) | PENDING - wire Defender Sentinel first |
| 3 | IC reviews alert in Defender dashboard | PENDING - wire Defender Sentinel first |
| 4 | Confirm it's a controlled test | DONE |
| 5 | Unpause: call setPaused(false) | PASS - Tx 0xce90d7... succeeded |
| 6 | Verify system returns to normal | PASS - paused() returns false |

## Transaction Evidence

**Pause TX**: 0x89d821c0c53d02f6d5fbfbdcbde4de6a8b54bbe872f02ef66887a2ba44e41d56
- Block: 51978896
- Timestamp: 2026-04-27T08:43:52Z
- From: 0x3F07367008158dC272Dd8A38812e1460eF5a390a
- Gas Used: 46,753

**Unpause TX**: 0xce90d74a0d803970ad59c0e4bd3d8fb85afaed254c8edef1682cc5ded8d26563
- Block: 51978957
- Timestamp: 2026-04-27T08:45:02Z
- From: 0x3F07367008158dC272Dd8A38812e1460eF5a390a
- Gas Used: 24,841

## Response Time

| Metric | Value |
|--------|-------|
| Pause to unpause | ~70 seconds |
| System downtime | ~70 seconds (controlled test) |
| Alert latency | To be measured when Defender Sentinel is wired |

## Verification Commands

```bash
# Step 1: Confirm pause state (should return 0x01 = true)
cast call 0x427c94150f3f700Dc2EDf7bCc97155A467E41F21 \
  "paused()" \
  --rpc-url https://rpc.hyperliquid-testnet.xyz/evm

# Step 2: Confirm event log
cast receipts 0x89d821c0c53d02f6d5fbffdcbde4de6a8b54bbe872f02ef66887a2ba44e41d56 \
  --rpc-url https://rpc.hyperliquid-testnet.xyz/evm

# Step 3: Confirm unpause restored state (should return 0x00 = false)
cast call 0x427c94150f3f700Dc2EDf7bCc97155A467E41F21 \
  "paused()" \
  --rpc-url https://rpc.hyperliquid-testnet.xyz/evm
```

## Items Pending (Require Manual Setup)

To complete G10, you must:
- [ ] Sign up at https://defender.openzeppelin.com
- [ ] Add StrategyExecutor contract (0x427c941...) to Defender
- [ ] Create Sentinel "Zentory-A1-PausedSet" for PausedSet(bool) event
- [ ] Configure email or Slack notification channel
- [ ] Capture screenshot of Defender Sentinel history showing PausedSet event
- [ ] Capture screenshot of alert notification received
- [ ] Save all evidence to this folder

## Expected Evidence Files

Save these to `docs/reports/g10-runbook-test-2026-04-27/`:
- `defender-sentinel-history.png` - Sentinel history showing PausedSet event
- `alert-email-or-slack.png` - Notification received (email or Slack)
- `defender-contract-events.png` - StrategyExecutor events tab in Defender
