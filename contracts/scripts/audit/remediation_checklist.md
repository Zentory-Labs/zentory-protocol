# ZENT Protocol — Remediation Checklist

**Date:** 2026-04-28
**Status:** FIXED (all Critical and High items resolved)

---

## ✅ Critical Fixes

### C-1: Access Control on `EpochScoring.setAccuracy()` / `setAccuracyBatch()`
- [x] Added `scoringOracle` state variable to `EpochScoring`
- [x] Added `UnauthorizedOracle(address caller)` custom error
- [x] Added `onlyOracle` guard (`if (msg.sender != scoringOracle)`) to `setAccuracy()`
- [x] Added same guard to `setAccuracyBatch()`
- [x] Added `setScoringOracle()` function with `ScoringOracleUpdated` event
- [x] Updated constructor to accept `_scoringOracle` parameter
- [x] Added `PriceFeedSet` event for `setPriceFeed()`
- [x] Replaced `require` with custom errors throughout
- [x] Added `ArraysLengthMismatch` error to `EpochScoring`
- [x] Added `EpochPayoutsApplied` event for keeper indexing
- [x] Added `ScoringOracleUpdated` event

**File:** `contracts/src/signals/EpochScoring.sol`

---

### C-2: Reentrancy in `SubscriptionVault.subscribe()` / `renewSubscription()` / `cancelSubscription()`
- [x] Added `ReentrancyGuard` import from OpenZeppelin
- [x] Changed `contract SubscriptionVault` to `contract SubscriptionVault is ReentrancyGuard`
- [x] Added `nonReentrant` modifier to `subscribe()`
- [x] Added `nonReentrant` modifier to `renewSubscription()`
- [x] Added `nonReentrant` modifier to `cancelSubscription()`
- [x] Reordered `subscribe()` — state updates BEFORE `safeTransferFrom`
- [x] Reordered `renewSubscription()` — state updates BEFORE `safeTransferFrom`
- [x] Reordered `cancelSubscription()` — state deletion BEFORE `safeTransfer`
- [x] Added `latestExpiration` cache mapping
- [x] Added `_recomputeLatestExpiration()` helper
- [x] `subscribe()` updates `latestExpiration[msg.sender]` when expiration > current
- [x] `renewSubscription()` updates `latestExpiration[msg.sender]` when newExpiration > current
- [x] `cancelSubscription()` calls `_recomputeLatestExpiration()` after burn

**File:** `contracts/src/signals/SubscriptionVault.sol`

---

### C-3: Unbounded Loop in `SignalRegistry.submitSignalBatch()`
- [x] Added `uint256 public constant MAX_BATCH_SIZE = 100`
- [x] Added `BatchSizeExceeded(uint256 size, uint256 max)` custom error
- [x] Added bounds check at start of `submitSignalBatch()`
- [x] Added `MAX_EXPIRY = 7 days` constant to `SignalRegistry`
- [x] Added `ExpiryTooFar(uint256 expiresAt, uint256 maxExpiry)` custom error
- [x] Added `MAX_EXPIRY` check to `submitSignal()`
- [x] Added `MAX_EXPIRY` check to `submitSignalBatch()`

**File:** `contracts/src/signals/SignalRegistry.sol`

---

## ✅ High Fixes

### H-1: Front-Running on Signal Submission (Nonce Race Condition)
- [x] In `submitSignal()`: nonce captured BEFORE digest construction
- [x] In `submitSignalBatch()`: pre-check nonce before signature verification (per-item)
- [x] Comment added explaining front-running protection rationale

**File:** `contracts/src/signals/SignalRegistry.sol`

---

### H-2: DOS in `SubscriptionVault.hasAccess()` — O(n) Token Iteration
- [x] Added `mapping(address => uint32) public latestExpiration` cache
- [x] `hasAccess()` now has O(1) fast path: returns `false` if `latestExpiration < block.timestamp`
- [x] `latestExpiration` updated on `subscribe()` (if new expiration > current)
- [x] `latestExpiration` updated on `renewSubscription()` (if new expiration > current)
- [x] `_recomputeLatestExpiration()` recomputes from remaining tokens on `cancelSubscription()`

**File:** `contracts/src/signals/SubscriptionVault.sol`

---

### H-3: Missing Events on `EpochScoring` State-Changing Functions
- [x] `setPriceFeed()` now emits `PriceFeedSet(assetId, feed)` event
- [x] `AccuracySet` event already present (no change needed)
- [x] `setAccuracy()` and `setAccuracyBatch()` already emit `AccuracySet` (no change needed)
- [x] Added `EpochPayoutsApplied` event from `_applyPayouts()` for keeper indexing

**File:** `contracts/src/signals/EpochScoring.sol`

---

## ✅ Medium Fixes

### M-1: `SignalRegistry.getProviderSignals()` Stub
- [x] Added `mapping(address => bytes32[]) public providerSignalIds`
- [x] `_submitSignal()` pushes signalId to `providerSignalIds[provider]`
- [x] `getProviderSignals()` now returns real data from `providerSignalIds`
- [x] Iterates only over requested index range `[from, to]`

**File:** `contracts/src/signals/SignalRegistry.sol`

---

### M-2: No Maximum Signal Expiry
- [x] Covered by C-3 fix (`MAX_EXPIRY = 7 days` enforcement)
- [x] Same constant and error used in both `submitSignal` and `submitSignalBatch`

**File:** `contracts/src/signals/SignalRegistry.sol`

---

## ✅ Low/Informational (No Code Changes Required)

### L-1: Integer Overflow in `EpochScoring.applyPayout()`
- [x] Verified safe: Solidity 0.8.x checked arithmetic prevents overflow
- [x] Documented in `self_audit_findings.md`

### I-1: Contracts Not Upgradeable
- [x] Documented in `self_audit_findings.md` as intentional design choice

### I-2: Critical Parameters Not Governance-Controlled
- [x] Documented in `self_audit_findings.md` — recommend future governance

### I-3: ZENT Token Assumptions
- [x] Documented in `self_audit_findings.md` — recommend ERC-20 interface guard

---

## 🔍 Verification Checklist

- [ ] `forge build` passes with no errors
- [ ] All custom errors compile correctly
- [ ] All events compile correctly
- [ ] `nonReentrant` modifier applied to correct functions
- [ ] Constructor signatures updated (new `scoringOracle` param)
- [ ] No new `require` statements left (prefer custom errors)
- [ ] No state changes after external calls in any modified function
- [ ] `MAX_BATCH_SIZE` enforced in `submitSignalBatch()`
- [ ] `MAX_EXPIRY` enforced in both `submitSignal()` and `submitSignalBatch()`
- [ ] `latestExpiration` cache correctly maintained across all write paths

---

## 📋 Files Modified

| File | Changes |
|------|---------|
| `contracts/src/signals/EpochScoring.sol` | Access control, events, constructor signature |
| `contracts/src/signals/SignalRegistry.sol` | MAX_BATCH_SIZE, MAX_EXPIRY, nonce order, providerSignalIds |
| `contracts/src/signals/SubscriptionVault.sol` | ReentrancyGuard, CEI pattern, latestExpiration cache |
| `contracts/scripts/audit/self_audit_findings.md` | New file — full findings report |
| `contracts/scripts/audit/remediation_checklist.md` | New file — this checklist |
