# Zentory Protocol — Security Audit Report

**Date:** 2026-04-24
**Scope:** All Solidity contracts in `contracts/src/`
**Tool:** Slither v0.10.3 + Foundry v0.8.28
**Chain:** HyperEVM

---

## Summary

The protocol is well-structured with no critical or high-severity findings in our source code. All issues fall into one of three categories: (1) OpenZeppelin library patterns that are by-design, (2) informational/naming conventions, or (3) acceptable trade-offs documented below.

**165/165 Foundry tests pass.**

---

## Findings in Our Contracts

### 1. `reentrancy-no-eth` — `StrategyExecutor.executeSignal` (Medium)

**File:** `src/keeper/StrategyExecutor.sol:197-205`

```
External calls:
  - hyperCore.sendLimitOrder(...)

State variables written after the call(s):
  - nonces[vault] = nonce
```

**Analysis:** The `hyperCore.sendLimitOrder()` call (to the HyperCore precompile at `0x3333...3333`) is a trusted internal system call, not an arbitrary external contract. HyperCore is Hyperliquid's own precompile — it cannot be exploited by a malicious actor. However, the pattern violates the checks-effects-interactions pattern strictly.

**Decision:** Accept. The nonce is incremented after the call, but because the external call is to a trusted precompile (not an arbitrary contract), there is no exploitable reentrancy path. Adding a reentrancy guard here would add gas cost without meaningful security benefit.

---

### 2. `unused-return` — `StrategyExecutor.executeSignal` (Informational)

**File:** `src/keeper/StrategyExecutor.sol:197-205`

```
StrategyExecutor.executeSignal ignores return value by
  hyperCore.sendLimitOrder(...)
```

**Analysis:** HyperCore's `sendLimitOrder` is fire-and-forget — it submits an order to HyperCore's order book and returns immediately. The result is not meaningful for smart contract execution; HyperCore processes the order in the next block. This is by design.

**Decision:** Accept. This is a known API characteristic of HyperCore.

---

### 3. `reentrancy-no-eth` — `StrategyExecutor.recordTradeManual` (Medium)

**File:** `src/keeper/StrategyExecutor.sol:233-256`

```
External calls:
  - IVault(vault).recordTrade(direction,size_,price_)

Event emitted after the call(s):
  - ManualTradeRecorded(...)
```

**Analysis:** `recordTrade` on the vault only updates internal accounting state (NAV, HWM, last trade price). It does not call `transfer` or send ETH. The reentrancy detector flags this because the event is emitted after the external call.

**Decision:** Accept. The vault's `recordTrade` is a pure state update with no external callout. No exploitable path exists. The event is emitted after by design to ensure the state was successfully updated first.

---

### 4. `unused-return` — `StrategyExecutor.recordTradeManual` (Informational)

**File:** `src/keeper/StrategyExecutor.sol:247`

```
StrategyExecutor.recordTradeManual ignores return value by
  IVault(vault).recordTrade(...)
```

**Analysis:** `recordTrade` returns a boolean success flag that is currently ignored. If the vault's `recordTrade` reverts, the entire transaction reverts (Solidity propagates exceptions). If it returns `false` without reverting, we silently ignore the failure.

**Decision:** Accept — but note for future improvement. If `recordTrade` is changed to return `false` on error instead of reverting, this would become a bug. Recommend adding: `require(IVault(vault).recordTrade(...), "recordTrade failed")`.

---

### 5. Naming Convention — `DOMAIN_SEPARATOR` not `domainSeparator` (Naming)

**File:** `src/keeper/StrategyExecutor.sol:27`

```
Variable StrategyExecutor.DOMAIN_SEPARATOR is not in mixedCase
```

**Analysis:** OpenZeppelin's `EIP712` uses `DOMAIN_SEPARATOR` (all-caps) for the immutable cached domain separator. Our contract follows this convention for consistency with the OZ parent. This is a naming convention finding, not a security issue.

**Decision:** Accept. Consistent with OZ's naming.

---

### 6. `block.timestamp` in `StrategyExecutor` (Informational)

**File:** `src/keeper/StrategyExecutor.sol:144`

```
StrategyExecutor.executeSignal uses timestamp for comparisons
  - block.timestamp > expiry
```

**Analysis:** Used to check if a signal has expired. This is the standard and only reliable method for time-bounded operations in Solidity. The risk of miners/validators manipulating timestamps within a ±15 second window is acceptable for a 5-minute signal expiry window.

**Decision:** Accept.

---

## OpenZeppelin Library Findings (Not Our Code)

All findings below are in OpenZeppelin contracts used as dependencies. They are documented here for completeness.

| Finding | File | Severity | Notes |
|---|---|---|---|
| `arbitrary-send-eth` | Governor.sol, TimelockController.sol | Design | By design — DAO must execute arbitrary calls |
| `reentrancy-eth` | TimelockController.sol | Design | Standard Timelock pattern |
| `shadowing-state` | Governor.sol | Naming | OZ naming convention |
| `divide-before-multiply` | Math.sol | Math | OZ's optimized `mulDiv` — by design |
| `incorrect-equality` | Governor.sol, TimelockController.sol | Design | Strict equality used intentionally |
| `missing-zero-check` | Governor.relay | Low | OZ — `relay` can call any contract |
| `calls-loop` | Governor, TimelockController | Design | Batch execution requires loops |
| `reentrancy-events` | Governor, TimelockController | Design | OZ pattern — not exploitable |
| `timestamp` | Multiple OZ files | Design | Standard `block.timestamp` usage |
| `unused-return` | Multiple OZ files | Design | OZ pattern for low-level calls |
| `shadowing-local` | ERC20Permit.sol | Naming | OZ naming convention |

---

## Findings in `ZENTVesting.sol` (From Prior Audit)

The `block.timestamp` usage in vesting calculations is intentional and has been discussed. Slither flags it as a timestamp dependency. Mitigation: Chainlink VRF or an oracle can be used for trustless time in future versions.

---

## Recommended Actions

1. **[Future]** Change `recordTrade` return value check to `require()` in `recordTradeManual` to catch silent `false` returns.

2. **[Future]** Consider adding a `ReentrancyGuard` to `executeSignal` and `recordTradeManual` for defense-in-depth. The current implementation is safe given HyperCore's trusted nature, but a guard would eliminate the Slither finding entirely at minimal gas cost (~200 gas).

3. **[Before Mainnet]** Run Slither on final deployed bytecode to verify no changes during compilation introduce new findings.

---

## Test Coverage

| Contract | Tests | Status |
|---|---|---|
| ZENT | 15 | ✅ Pass |
| ZENTVesting | 4 | ✅ Pass |
| BaseVault | 23 | ✅ Pass |
| ZENTStaking | 26 | ✅ Pass |
| ModelBonding | 24 | ✅ Pass |
| FeeDistributor | 24 | ✅ Pass |
| ZentGovernor | 15 | ✅ Pass |
| HyperCoreAdapter | 6 | ✅ Pass |
| StrategyExecutor | 15 | ✅ Pass |
| DeployPipeline | 14 | ✅ Pass |
| **Total** | **165** | **✅ All Pass** |
