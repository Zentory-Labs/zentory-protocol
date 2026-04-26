# Security Findings — April 25–27, 2026

## Slither Analysis (April 27, 2026)

**Command:** `slither .` (with `contracts/slither.config.json`)
**Result:** 0 HIGH / CRITICAL findings in project contracts. 38 informational findings remain (naming conventions only).

### Slither Suppressions (updated April 27, 2026)

`contracts/slither.config.json` is now committed. Run `slither .` to use it. The config suppresses all OpenZeppelin informational findings plus dead-code (the only project-level finding was `_assetForVault` which is now removed).

---

## Contract Test Results (April 27, 2026)

**Tool:** Foundry 1.5.1-stable
**Command:** `forge test`
**Result:** ✅ **203 tests passing, 0 failures**

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
| `DigestParityTest` | 6 | ✅ |
| **Total** | **203** | **✅** |

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

## Fixes Applied

### April 27, 2026 — Investor-Readiness Hardening

1. **`StrategyExecutor.sol`** — `authorizedSigner` now defaults to `msg.sender` in constructor (prevents bricked keeper). Added `AuthorizedSignerSet` event. Implemented leverage check — rejects signals where `positionValue > maxLeverageBPS * 1e6`. Removed dead `_assetForVault` helper.

2. **`BaseVault.sol`** — Added `ReentrancyGuard` + `nonReentrant` to `claimFees()`. Added `onlyRole(KEEPER_ROLE)` to `evaluateFees()`. Added automatic `checkCircuitBreaker()` callable by anyone (reads NAV drawdown, auto-triggers if `drawdownBPS >= circuitBreakerDrawdownBPS`). Added `CircuitBreakerAutoTriggered` and `PositionClosed` events.

3. **`ZentGovernor.sol`** — `proposalThreshold()` now returns `minProposalThreshold` instead of hardcoded 0. `quorum()` now uses `totalVeSupply()` instead of raw `totalSupply()`.

4. **`ZENTStaking.sol`** — Added `totalVeSupply` tracking (updated on stake/increaseAmount/withdraw) for accurate governance quorum.

5. **`IZENTStaking.sol`** — Added `totalVeSupply()` view.

6. **`DEPLOYMENT.md`** — Fixed fee split: 50% buyback, 25% GP engine, 15% insurance, 10% treasury. Fixed `Zentroller` description (no pause capability). Removed non-existent management fee.

7. **`Providers.tsx`** — Removed hardcoded WalletConnect project ID fallback. Added runtime check + conditional connector spread so build doesn't crash when env var is absent.

8. **`monitoring-setup.md`** — Created step-by-step guide for Tenderly/Defender wiring, alert routing, and G9/G10 evidence collection.

9. **`slither.config.json`** — Created with suppressions for all OZ informational findings.

### April 25, 2026

1. **`ZentGovernor.sol`** — Removed invalid `supportsInterface(bytes4).override(Governor, GovernorTimelockControl)`.
2. **`StrategyExecutor.t.sol`** — Updated `_makeDigest` call to include `price` parameter.
3. **`signer.py`** — Updated `_TYPEHASH` to match new `TradeSignal` struct; added `\x19\x01` prefix.
4. **`HyperCoreAdapter.sol`** — Inline assembly NatSpec fix.
5. **Foundry test suite** — Fixed `vm.sign` calls; added fuzz + invariant suites.
6. **Playwright tests** — Created full smoke + security test suite.

---

## Project-Specific Findings

| ID | Severity | File | Finding | Remediation | Status |
|----|----------|------|---------|-------------|--------|
| S-01 | LOW | `StrategyExecutor.sol` | `transferAdmin` does immediate `grantRole` + `renounceRole` (no two-step delay) | Deploy script calls after governance is live | **Documented** |
| S-02 | LOW | `BaseVault.sol` | `claimFees` uses `forceApprove` before `accumulate` | Intentional for fee-on-transfer/rebasing assets | **Fixed** |
| S-03 | LOW | `StrategyExecutor.sol` | `DOMAIN_SEPARATOR` missing `chainId` (defense-in-depth) | `chainId` already included in constructor | **Fixed** |
| S-04 | LOW | `HyperCoreAdapter.sol` | Inline assembly for CoreWriter call | Documented in code comments | **Documented** |
| S-05 | INFO | `ZentGovernor.sol` | `TimelockController` misconfiguration risk | Deploy scripts enforce 48h minimum | **Configured** |

---

## Remaining Action Items

| ID | Priority | Description | Owner | Status |
|----|----------|-------------|-------|--------|
| R-01 | HIGH | Add `chainId` to StrategyExecutor EIP-712 domain separator | Smart contracts | **DONE** (was already present) |
| R-02 | HIGH | Write `test_digest_parity.py` — EIP-712 parity fixture | Engine | **DONE** |
| R-03 | HIGH | Run full Playwright test suite against testnet | CI/CD | PENDING (needs live deployment) |
| R-04 | MEDIUM | Add `slither.config.json` | DevOps | **DONE** |
| R-05 | MEDIUM | Manual pentest: authorized signer key compromise (P4.1) | Security | PENDING (needs live deployment) |
| R-06 | MEDIUM | Manual pentest: front-running signal scenario (P4.2) | Security | PENDING (needs live deployment) |
| R-07 | LOW | Add `acceptAdmin` two-step pattern to StrategyExecutor | Smart contracts | PENDING |
| R-08 | LOW | Deploy to HyperEVM testnet and run full integration | DevOps | PENDING |

---

*Generated: 2026-04-27*
*Tool versions: Foundry 1.5.1-stable, Slither 0.11.5, Playwright 1.x, Next.js 16.2.4*
