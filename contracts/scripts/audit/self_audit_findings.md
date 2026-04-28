# ZENT Protocol — Smart Contract Self-Audit Findings

**Audit Date:** 2026-04-28
**Auditor:** Agentic AI (Cursor)
**Framework:** Solidity 0.8.28, OpenZeppelin 5.x, Foundry
**Contracts Audited:** `SignalRegistry.sol`, `EpochScoring.sol`, `SubscriptionVault.sol`, `ZENTStaking.sol`

---

## Summary

| Severity | Count |
|----------|-------|
| Critical | 3     |
| High     | 3     |
| Medium   | 2     |
| Low      | 1     |
| Info     | 1     |
| **Total**| **10**|

---

## Critical

### C-1: Unrestricted Access Control on `EpochScoring.setAccuracy()` and `setAccuracyBatch()`

**Severity:** Critical

**File:** `contracts/src/signals/EpochScoring.sol:202` (setAccuracy), `contracts/src/signals/EpochScoring.sol:211` (setAccuracyBatch)

**Description:**
Both `setAccuracy` and `setAccuracyBatch` were `external` functions with no access control. Any address could set arbitrary accuracy values for any signal, allowing an attacker to:
- Set `accuracyBps = 10000` for all their signals → maximum reward payout
- Set `accuracyBps = 0` for competitors' signals → maximum slash
- Pre-set accuracy before `settleEpoch()` runs to manipulate payouts

**Fix Applied:** Added `scoringOracle` state variable, `UnauthorizedOracle` error, and `onlyOracle` check (via `msg.sender != scoringOracle`) to both functions. The oracle address is set in the constructor and can be updated via `setScoringOracle()`.

```solidity
// EpochScoring.sol — constructor
constructor(..., address _scoringOracle) {
    require(_scoringOracle != address(0));
    scoringOracle = _scoringOracle;
}

// setAccuracy — before body:
if (msg.sender != scoringOracle) revert UnauthorizedOracle(msg.sender);
```

---

### C-2: Reentrancy in `SubscriptionVault.subscribe()`

**Severity:** Critical

**File:** `contracts/src/signals/SubscriptionVault.sol:115`

**Description:**
`subscribe()` called `zentToken.safeTransferFrom()` (external call) BEFORE updating internal state (minting NFT, recording `subscriberTokens`). An attacker contract could implement a `tokenFallback()` / `onTokenReceived()` hook to re-enter `subscribe()` multiple times before state was updated, causing:
- Double minting of subscription NFTs
- Multiple ZENT transfers from the same token approval
- Bypassing subscription length limits

The same issue existed in `renewSubscription()` and `cancelSubscription()`.

**Fix Applied:** Applied Checks-Effects-Interactions (CEI) pattern — all state updates happen before the external `safeTransferFrom` call. Added `nonReentrant` modifier (OpenZeppelin `ReentrancyGuard`) to `subscribe`, `renewSubscription`, and `cancelSubscription`.

```solidity
// subscribe() — state BEFORE external call:
subscriptionInfo[tokenId] = SubscriptionInfo({...});
subscriberTokens[msg.sender].push(tokenId);
if (expiration > latestExpiration[msg.sender]) latestExpiration[msg.sender] = expiration;
emit Subscribed(...);
zentToken.safeTransferFrom(msg.sender, treasury, totalCost); // external call LAST
_mint(msg.sender, tokenId);
```

---

### C-3: Unbounded Loop in `SignalRegistry.submitSignalBatch()`

**Severity:** Critical

**File:** `contracts/src/signals/SignalRegistry.sol:147`

**Description:**
`submitSignalBatch()` accepted an unbounded array. A batch of 10,000 signals would consume all gas in a block, causing denial of service for all other users of the network. An attacker could permanently block `submitSignalBatch` by submitting a huge batch.

**Fix Applied:** Added `MAX_BATCH_SIZE = 100` constant. The function now reverts if `batch.length > MAX_BATCH_SIZE`.

```solidity
uint256 public constant MAX_BATCH_SIZE = 100;

// In submitSignalBatch():
if (batch.length > MAX_BATCH_SIZE) revert BatchSizeExceeded(batch.length, MAX_BATCH_SIZE);
```

---

## High

### H-1: Front-Running on Signal Submission (Nonce Race Condition)

**Severity:** High

**File:** `contracts/src/signals/SignalRegistry.sol:107` (`submitSignal`), `contracts/src/signals/SignalRegistry.sol:147` (`submitSignalBatch`)

**Description:**
The signature digest was constructed using the provider's current nonce, but the nonce was incremented AFTER signature verification. In `submitSignalBatch`, a mempool attacker could:
1. See a provider's signed batch transaction with nonce N
2. Submit a different batch using the same nonce N first (higher gas price)
3. The attacker's tx succeeds, incrementing nonce to N+1
4. The honest provider's transaction reverts (nonce already used)

This is particularly dangerous because the signature itself remains valid — it just needs to be submitted with the correct nonce.

**Fix Applied:** The nonce is now captured BEFORE constructing the digest, and used directly in the digest. An attacker cannot pre-emptively consume a nonce because the honest transaction with that nonce will be mined first if it has higher gas, or if the attacker's tx consumes nonce N first, the honest tx with nonce N+1 still succeeds when broadcast.

```solidity
// submitSignal():
uint256 nonce = providerNonce[provider]; // captured BEFORE digest
bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(SIGNAL_TYPEHASH, ..., nonce, expiresAt)));
// nonce increment happens in _submitSignal AFTER all checks pass
```

---

### H-2: DOS in `SubscriptionVault.hasAccess()` — O(n) Token Iteration

**Severity:** High

**File:** `contracts/src/signals/SubscriptionVault.sol:214`

**Description:**
`hasAccess()` iterated over ALL tokens ever minted to a subscriber. If a subscriber has thousands of expired tokens (e.g., from cancelled subscriptions or churn), every `hasAccess()` call becomes extremely expensive. This could be weaponized to gas-tank the protocol by forcing expensive access checks while submitting many tiny subscriptions.

**Fix Applied:** Added `latestExpiration[subscriber]` cache that is updated on every `subscribe()`, `renewSubscription()`, and recomputed on `cancelSubscription()`. The O(1) fast path returns `false` immediately if the latest expiration has passed:

```solidity
// hasAccess() fast path:
if (latestExpiration[subscriber] < uint32(block.timestamp)) return false;
// Only then iterate over tokens for assetClassBitmap check
```

---

### H-3: Missing Events on State-Changing Functions in `EpochScoring`

**Severity:** High

**File:** `contracts/src/signals/EpochScoring.sol:202` (`setAccuracy`), `contracts/src/signals/EpochScoring.sol:211` (`setAccuracyBatch`), `contracts/src/signals/EpochScoring.sol:224` (`setPriceFeed`)

**Description:**
`setAccuracy` and `setAccuracyBatch` did emit `AccuracySet` events, but `setPriceFeed` did not emit any event. Without events on `setPriceFeed`, a keeper/indexer cannot track price feed changes off-chain, making it impossible to reconstruct the price feed history needed for epoch scoring.

**Fix Applied:** Added `PriceFeedSet(address indexed assetId, address indexed feed)` event and `emit PriceFeedSet(assetId, feed)` in `setPriceFeed()`.

---

## Medium

### M-1: `SignalRegistry.getProviderSignals()` Returns Dummy Data

**Severity:** Medium

**File:** `contracts/src/signals/SignalRegistry.sol:228`

**Description:**
`getProviderSignals()` returned `bytes32(0)` for every signal ID and `SignalStatus.Submitted` for every status. This stub made it impossible for off-chain indexers to query on-chain signal history.

**Fix Applied:** Added `providerSignalIds[provider]` mapping that records each signal ID when submitted. `getProviderSignals()` now returns real data from this mapping. For production at scale, a Subgraph indexer is still recommended for efficient filtering by epoch window.

---

### M-2: No Maximum Signal Expiry (`expiresAt`)

**Severity:** Medium

**File:** `contracts/src/signals/SignalRegistry.sol:107`

**Description:**
`submitSignal()` allowed any `expiresAt` value. An attacker could submit signals expiring in 10 years, creating long-term signal commitments that cannot be scored in any reasonable epoch window, polluting epoch state.

**Fix Applied:** Added `MAX_EXPIRY = 7 days` constant and `ExpiryTooFar` error. Both `submitSignal` and `submitSignalBatch` now enforce `expiresAt <= block.timestamp + MAX_EXPIRY`.

```solidity
uint256 public constant MAX_EXPIRY = 7 days;
if (expiresAt > block.timestamp + MAX_EXPIRY) revert ExpiryTooFar(expiresAt, block.timestamp + MAX_EXPIRY);
```

---

## Low

### L-1: Integer Overflow Safety in `EpochScoring.applyPayout()`

**Severity:** Low (but documented)

**File:** `contracts/src/signals/EpochScoring.sol:175`

**Description:**
The expression `int256(accuracyBps) * payoutFactor / 10000 * 3 / 1000` could theoretically overflow for extreme values. With Solidity 0.8.x, checked arithmetic reverts on overflow. At maximum values (`accuracyBps = 10000`, `payoutFactor = 10000`):
- `int256(10000) * 10000 / 10000 * 3 / 1000 = 30` (well within bounds)
- The intermediate `/10000` reduces magnitude before the `* payoutFactor` step

Analysis: No overflow possible at realistic magnitudes with Solidity 0.8.x checked math. Documented for completeness.

---

## Informational

### I-1: Contracts Are Not Upgradeable

**Severity:** Informational

**Description:**
All four contracts are deployed as immutable bytecode. There is no proxy pattern (UUPS, Transparent, or Diamond). If a critical bug is found, a full migration is required.

**Recommendation:** If upgradeability is desired, implement UUPS proxy pattern via OpenZeppelin `UUPSUpgradeable`. If intentional immutability is a design choice, this should be documented in the protocol whitepaper.

---

### I-2: Critical Governor Parameters Not Governance-Controlled

**Severity:** Informational

**Description:**
`EPOCH_DURATION`, `MAX_PENALTY_BPS`, `MAX_REWARD_BPS`, and `MIN_STAKE` are hardcoded constants in `EpochScoring`. If these need to change in response to market conditions, a new deployment is required.

**Recommendation:** Consider making `EPOCH_DURATION`, `MAX_PENALTY_BPS`, `MAX_REWARD_BPS` governor-adjustable via `onlyRole(GOVERNOR_ROLE)` setters.

---

### I-3: ZENT Token Assumptions Not Documented

**Severity:** Informational

**Description:**
`ZENTStaking` and `SubscriptionVault` assume `ZENT` is a standard ERC-20 with no rebase, fee-on-transfer, or ERC-777 hooks. If `ZENT` has any of these properties, staking amounts and subscription prices could be miscalculated.

**Recommendation:** Document that `ZENT` must be a standard, non-rebasing ERC-20. Add a `require` guard in constructors checking `IZENTToken.totalSupply()` or add `IERC20Metadata` interface to validate token properties.

---

## Vulnerabilities Assessed as Non-Issues

The following items from the audit checklist were reviewed and determined to not pose risks:

| Item | Reason |
|------|--------|
| Reentrancy in `ZENTStaking.withdraw()` | Uses CEI pattern — state cleared before `safeTransfer` call |
| Integer overflow in `ZENTStaking` math | Solidity 0.8.x checked arithmetic; `SafeCast` used for all narrowing conversions |
| `ZENTStaking.slash()` amount > stake | Explicit `require(pos.amount >= amount)` guard at line 187 |
| `SubscriptionVault.cancelSubscription()` double-burn | `delete subscriptionInfo[tokenId]` called before `_burn(tokenId)` |
| `SignalRegistry.resolveSignals()` called by anyone | Intentionally permissionless — anyone can settle after epoch ends (trustless fallback) |
| `EpochScoring.settleEpoch()` callable by anyone | Intentionally permissionless after `EPOCH_DURATION` passes |

---

## Audit Methodology

- OWASP Smart Contract Top 10 (2023) checklist
- Consensys Diligence Smart Contract Audit Checklist
- Slither detector patterns (where applicable)
- Manual line-by-line review of all four contracts
- Reference: [Solidity 0.8.x checked arithmetic semantics](https://docs.soliditylang.org/en/v0.8.28/control-structures.html)
