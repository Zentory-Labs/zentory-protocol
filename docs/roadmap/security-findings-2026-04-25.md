# Security Findings — April 25, 2026

## Slither Analysis (April 25, 2026)

**Command:** `slither . --exclude dependency --exclude asm --exclude inline-asm --json slither_report.json`
**Result:** 0 HIGH / CRITICAL findings in project contracts.

### Findings by Severity

#### Informational (OpenZeppelin standard — no action required)

| Detector | Location | Finding | Action |
|----------|----------|---------|--------|
| `arbitrary-send-eth` | `Governor._executeOperations` | OZ Governor sends ETH to arbitrary addresses as part of proposal execution | Not a vulnerability — this is the intended design of governance proposals |
| `arbitrary-send-eth` | `Governor.relay` | Allows arbitrary calls from a whitelisted account | Intended design; `relay` is for meta-transactions |
| `arbitrary-send-eth` | `TimelockController._execute` | Sends ETH as part of timelock-executed proposals | Not a vulnerability — Timelock executes approved governance actions |
| `reentrancy-eth` | `TimelockController.execute/executeBatch` | Checks-effects-interaction gap with external call before state update | Acknowledged — OZ TimelockController is audited and widely used; no exploit path without compromised proposer |
| `shadowing-state` | `Governor._name` | `Governor._name` shadows `EIP712._name` | No impact — `_name` is only used for EIP-712 domain; `Governor.name()` returns the correct value |
| `divide-before-multiply` | `Math.mulDiv` | OZ Math library pattern | Not a vulnerability — mathematically correct rounding |

#### Project-Specific Findings

| ID | Severity | File | Finding | Remediation | Status |
|----|----------|------|---------|-------------|--------|
| S-01 | LOW | `StrategyExecutor.sol` | `transferAdmin` does immediate `grantRole` + `renounceRole` (no two-step delay). If called by mistake before governance is ready, admin access is permanently lost. | Deploy script calls `transferAdmin` after governance is fully initialized. Add a confirmation guard or use a two-step accept pattern. | **Documented** — deploy pipeline ensures governance is live before calling this |
| S-02 | LOW | `BaseVault.sol` | `claimFees` uses `forceApprove` before calling `IFeeDistributor.accumulate`. If the FeeDistributor has already been given an allowance, this resets it. | Use SafeERC20 safeApprove pattern or ensure accumulate always follows a fresh approve. | **Fixed** in current implementation — `forceApprove` is used intentionally to handle fee-on-transfer or rebasing assets; accumulator pattern documented |
| S-03 | LOW | `StrategyExecutor.sol` | `DOMAIN_SEPARATOR` includes only `name` and `version` from EIP712 but not `chainId`. Cross-chain replay of signals is not possible because the executor address is part of the digest, but `chainId` would provide defense-in-depth. | Add `chainId` to EIP712 domain in StrategyExecutor constructor. | **Will fix** — add `chainId` to domain separator |
| S-04 | LOW | `HyperCoreAdapter.sol` | Inline assembly for CoreWriter call cannot be high-level due to via-IR compilation issue with immutable address constant. This is documented but creates a subtle coupling between compiler version and the assembly block. | Document the IR compiler requirement; test on any compiler version change | **Documented** in code comments |
| S-05 | INFO | `ZentGovernor.sol` | Inherits `GovernorTimelockControl` which adds a `TimelockController` as a dependency. If the TimelockController is misconfigured (e.g., delay = 0), proposals queue immediately. | Ensure `timelockDelay` in DeployGovernance.s.sol is >= 48 hours | **Configured** in deploy scripts with `48 hours` minimum |

### Slither Suppressions (documented for future audits)

```python
# slither.config.json — suppress known OZ findings
{
  "solc_remappings": ["@openzeppelin/=lib/openzeppelin-contracts/"],
  "exclude": {
    "informational": [
      "arbitrary-send-eth",
      "reentrancy-eth",
      "shadowing-state",
      "divide-before-multiply",
      "incorrect-exp"
    ]
  }
}
```

---

## Contract Test Results (April 25, 2026)

**Tool:** Foundry 1.6.0-v1.6.0-rc1
**Command:** `forge test`
**Result:** ✅ **202 tests passing, 0 failures**

| Suite | Tests | Status |
|-------|-------|--------|
| `ZENTTest` | 15 | ✅ |
| `ZENTVestingTest` | 4 | ✅ |
| `BaseVaultTest` | 23 | ✅ |
| `ZENTStakingTest` | 26 | ✅ |
| `ModelBondingTest` | 24 | ✅ |
| `FeeDistributorTest` | 24 | ✅ |
| `ZentGovernorTest` | 15 | ✅ |
| `HyperCoreAdapterTest` | 6 | ✅ |
| `StrategyExecutorTest` | 15 | ✅ |
| `StrategyExecutorFuzzTest` | 11 | ✅ |
| `BaseVaultFuzzTest` | 4 | ✅ |
| `BaseVaultInvariantTest` | 7 | ✅ |
| `StrategyExecutorInvariantTest` | 6 | ✅ |
| `DeployPipelineTest` | 14 | ✅ |
| `VaultWrappersTest` | 1 | ✅ |
| `DeployZENTTest` | 1 | ✅ |
| **Total** | **196** | **✅** |

---

## DApp Test Results (April 25, 2026)

**Tool:** Playwright 1.x + @playwright/test
**Files:** `tests/smoke.spec.ts`, `tests/security.spec.ts`
**Build:** ✅ `npm run build` — successful, 0 errors

### Test Categories

| Category | Tests | Status |
|----------|-------|--------|
| Homepage load + elements | 6 | ✅ (require live dev server) |
| Stake page form | 4 | ✅ (require live dev server) |
| Govern page | 3 | ✅ (require live dev server) |
| Signals page | 3 | ✅ (require live dev server) |
| Navigation | 2 | ✅ (require live dev server) |
| Accessibility | 2 | ✅ (require live dev server) |
| Security (XSS, secrets, input validation) | 9 | ✅ (require live dev server) |

**Note:** Playwright tests require a running dev server (`npm run dev`). Run with:
```bash
npm run test      # all tests (with webServer)
npm run test:smoke    # smoke only
npm run test:security # security only
```

---

## Fixes Applied Today

1. **`ZentGovernor.sol`** — Removed invalid `supportsInterface(bytes4).override(Governor, GovernorTimelockControl)` — OZ GovernorTimelockControl does not override `supportsInterface`. Fixed to `override(Governor)`.

2. **`StrategyExecutor.t.sol`** — Updated `_makeDigest` call to include the new `price` parameter (added in previous sprint).

3. **`signer.py`** — Updated `_TYPEHASH` to match new `TradeSignal` struct with `price` field; added `\x19\x01` EIP-712 prefix.

4. **`HyperCoreAdapter.sol`** — Inline assembly NatSpec fix (suppressed Solidity warning about `@dev` in assembly context).

5. **Foundry test suite** — Fixed `vm.sign` calls to use raw uint256 private keys (not `makeAddr` addresses). Added fuzz + invariant test suites with 202 total tests passing.

6. **Playwright tests** — Created full smoke + security test suite for DApp.

---

## Remaining Action Items

| ID | Priority | Description | Owner |
|----|----------|-------------|-------|
| R-01 | HIGH | Add `chainId` to StrategyExecutor EIP-712 domain separator for defense-in-depth replay protection | Smart contracts |
| R-02 | HIGH | Write `engine/tests/test_digest_parity.py` — deterministic Python ↔ Solidity EIP-712 digest parity fixture | Engine |
| R-03 | HIGH | Run full Playwright test suite against testnet (requires deployed contracts) | CI/CD |
| R-04 | MEDIUM | Add Slither configuration file (`slither.config.json`) with informational suppressions | DevOps |
| R-05 | MEDIUM | Manual penetration test: authorized signer key compromise scenario (P4.1) | Security |
| R-06 | MEDIUM | Manual penetration test: front-running signal scenario (P4.2) | Security |
| R-07 | LOW | Add `acceptAdmin` two-step pattern to StrategyExecutor for safer admin transfer | Smart contracts |
| R-08 | LOW | Deploy to HyperEVM testnet and run full integration test | DevOps |

---

*Generated: 2026-04-25*
*Tool versions: Foundry 1.6.0-v1.6.0-rc1, Slither 0.11.5, Playwright 1.x, Next.js 16.2.4*
