# Audit Handoff — 2026-Q3 Refresh

This document is the change ledger for the Q3 audit refresh. It enumerates
every contract that was modified, the audit finding each change addresses,
the regression test that locks the behaviour, and the runtime verification
that proves it works end-to-end.

Reviewers should use this as the table of contents when re-auditing.

---

## Summary

- **410 forge tests pass**, 0 fail, 1 skipped (intentional `vm.ffi` parity).
- **24 new audit tests** across 6 files added in this pass.
- **29 Dependabot alerts** cleared via dependency bumps.
- **1 real cross-contract CEI bug** caught by runtime execution (not visible
  to the static `solc` validator): `HyperCoreAdapter.sendLimitOrder`
  rejected the executor's close-signal size=0 path, eating the nonce advance.

---

## Smart-contract surface touched

### `contracts/src/vaults/BaseVault.sol`

| Audit finding | Severity | Fix | Test |
|---|---|---|---|
| `claimFees()` reverts when `feeRecipient` is a contract that does not implement `IFeeDistributor` correctly | H-2 (audit) | Wrap the `accumulate` call in `try/catch`; on failure, transfer fees directly to the recipient and emit `FeeRecipientFallbackUsed`. Zeroing of `performanceFeeAccrued` moved AFTER the transfer so a failed transfer/approval does not strand accrued fees. | (covered by manual review + `test_claimFees_*` in the existing suite) |
| `redeemEmergency` stranded `performanceFeeAccrued` against departed depositors, enabling later `claimFees()` to drain value the protocol never earned | H-1 (Berkay Çarıkçıoğlu) | Proportionally decrement `performanceFeeAccrued` for the redeemed shares. | `test/vaults/SpotVaultEmergencyH1.t.sol` — 2 tests |

### `contracts/src/fees/FeeDistributor.sol`

| Audit finding | Severity | Fix | Test |
|---|---|---|---|
| `FeesDistributed` event did not separately disclose the buyback-pool dust | L (audit) | Emit `dust` as its own field in `FeesDistributed`. Order matches CEI: emit BEFORE external transfers. | `test/fees/FeeDistributor.t.sol::test_distributeEmitsEvent` |

### `contracts/src/interfaces/IFeeDistributor.sol`

| Audit finding | Severity | Fix | Test |
|---|---|---|---|
| Event signature mismatch with implementation after dust split | L (audit) | Add `buybackDust` field to `FeesDistributed`. | `test/fees/FeeDistributor.t.sol` (compile-time) |

### `contracts/src/keeper/StrategyExecutor.sol`

| Audit finding | Severity | Fix | Test |
|---|---|---|---|
| Signal replay: nonce not consumed when external `CoreWriter` call reverts | H-3.1 (audit) | CEI: set `nonces[vault] = nonce` BEFORE the external `sendLimitOrder` call. | `test/keeper/StrategyExecutorH3.t.sol::test_cei_nonceConsumedOnFailedCoreWriter` |
| `expiry = type(uint256).max` allowed a signed signal to be hoarded and replayed against any future nonce | H-3.2 (audit) | Cap signal expiry to `block.timestamp + MAX_SIGNAL_EXPIRY` (7 days). Same cap applied to `executeRebalance`. | `test/keeper/StrategyExecutorH3.t.sol::test_executeSignal_rejectsExpiryBeyondCap`, `test_executeRebalance_rejectsExpiryBeyondCap` |
| Close signal (direction=2) with `size=0` rejected outright | H-3.3 (audit) | Allow no-op close as a marker-nonce increment. | `test/keeper/StrategyExecutorH3.t.sol::test_closeSignalWithZeroSizeAccepted`, `test_closeSignalBypassesPerVaultMaxPositionSize`, `test_closeSignalStillRevertsOnCapIfNonZero` |

### `contracts/src/keeper/HyperCoreAdapter.sol`

| Audit finding | Severity | Fix | Test |
|---|---|---|---|
| **`sendLimitOrder` reverted on close-signal size=0, eating the executor's CEI nonce-set** (cross-contract bug caught only by runtime tests) | **CRITICAL** | Skip the `sz==0` check when `reduceOnly=true` (close signals may carry zero size). | `test/keeper/StrategyExecutorH3.t.sol::test_closeSignalWithZeroSizeAccepted` + `test/keeper/HyperCoreAdapterC2.t.sol` |

### `contracts/src/staking/ZENTStaking.sol`

| Audit finding | Severity | Fix | Test |
|---|---|---|---|
| `withdraw()` decrements `totalVeSupply` by `_veAt(now)`; a future accounting drift on another code path could underflow `totalStaked` and `totalVeSupply` | H-2 (audit) | Defensive clamp: `oldVeClamped = min(oldVe, totalVeSupply)`, `amountClamped = min(amount, totalStaked)`. Emit `VeSupplyDriftDetected` when the clamp engages. | `test/staking/ZENTStakingH2.t.sol` — 2 tests |

### `contracts/src/airdrop/MerkleDistributor.sol`

| Audit finding | Severity | Fix | Test |
|---|---|---|---|
| `sweep` used `require(recipient != address(0), ...)` instead of the codebase-wide typed-error pattern | L (audit, style) | Replaced with `if (recipient == address(0)) revert ZeroRecipient()`. Added `error ZeroRecipient()`. | (covered by existing MerkleDistributor suite) |

### `contracts/src/signals/SignalRegistry.sol`

| Audit finding | Severity | Fix | Test |
|---|---|---|---|
| `maxEpochSignals` ceiling not exposed for off-chain monitoring | L (audit, observability) | Added public getter. | `test/signals/SignalRegistryH4.t.sol` — 2 tests |

---

## Test files added

| File | Tests | Covers |
|---|---|---|
| `test/keeper/HyperCoreAdapterC2.t.sol` | 2 | C-2 CoreWriter failure surface |
| `test/keeper/StrategyExecutorH3.t.sol` | 6 | CEI nonce-on-failure, expiry cap, close-signal size=0, per-vault cap bypass for close |
| `test/signals/SignalRegistryH4.t.sol` | 2 | `maxEpochSignals` exposure + cap value |
| `test/staking/ZENTStakingH2.t.sol` | 2 | Drift clamp + happy-path clears `totalStaked` |
| `test/vaults/BaseVaultPhantomNav.t.sol` | 10 | C-1 phantom-NAV regression + fee cap + emergency redeem pro-rata |
| `test/vaults/SpotVaultEmergencyH1.t.sol` | 2 | H-1 stranded-fee decrement |

---

## Modified test files (pre-existing) that fixed)

| File | Change |
|---|---|
| `test/fees/FeeDistributor.t.sol` | Updated `test_distributeEmitsEvent` to expect `dust=0` (divisible-by-100 amounts have no rounding remainder) |
| `test/vaults/BaseVaultNavAndLeverage.t.sol` | Pinned pre-fix (vulnerable) behaviour was rewritten to assert post-fix settle-able NAV. 4 tests updated. |
| `test/crosslanguage/DigestParity.t.sol` | `expiry = type(uint256).max` replaced with `+1h` so the test no longer trips the new `MAX_SIGNAL_EXPIRY` cap |
| `test/script/RedeploySignalRegistry.t.sol` | `setUp` switched to `startPrank/stopPrank` so prank state is cleared between tests |

---

## Static-analysis / tooling

### `contracts/validate-tests.js`

Comprehensive stub layer for `forge-std` (Vm + Test + console2) and OpenZeppelin's `ERC20Mock`. Required because the project's CI does not have Foundry installed in every contributor's environment — `solc` is invoked directly to syntax- and type-check all test files.

The stub layer grew iteratively to cover:
- `Vm` interface cheatcodes: `prank`, `startPrank`, `stopPrank`, `warp`, `roll`, `deal`, `expectRevert`, `expectEmit`, `mockCall`, `clearMockedCalls`, `recordLogs`, `getRecordedLogs`, `label`, `addr`, `env*`, `envOr`, `sign`, `assume`, `store`, `load`, `chainId`, `skip`, `toString`, `ffi`, `parse*`, `toBytes32`, `parseJsonBytes32`, `parseJsonAddress`
- `Test` contract: `makeAddr`, `makeAccount`, `bound` overloads, full DSTest-style `assertEq`/`assertGt`/`assertLt`/`assertLe`/`assertGe`/`assertTrue`/`assertFalse`/`assertNotEq`/`assertApproxEqAbs`/`assertApproxEqRel` overloads for uint256/int256/address/bytes32/bool/string/bytes
- `console2` / `console` libraries with disambiguated overloads
- `ERC20Mock` inheriting OpenZeppelin's `ERC20` with full standard interface

### Dependabot (29 alerts cleared)

```
next         16.2.6   → ^16.3.3    (closes 9 HIGH CVEs)
axios        ^1.16.0  → 1.20.0     (closes 13 prototype-pollution/DoS CVEs)
vite         ^2.1.0   → 8.2.2      (closes 3 dev-server CVEs incl. file-disclosure)
vitest       ^2.1.0   → 4.1.11     (closes the CRITICAL Vitest-UI file-read CVE)
esbuild      ^0.21    → 0.28.2     (closes dev-server request forgery)
ws           8.20.0   → 8.21.3     (closes fragment-DoS)
form-data    4.0.5    → 4.0.6      (closes CRLF injection)
@openzeppelin/contracts ^5.1.0 → ^5.6.1   (current stable)
```

`npm audit` on every manifest (`package.json`, `contracts/package.json`, `contracts/keeper/package.json`) reports **0 vulnerabilities** after the bump.

---

## Runtime verification

```
forge build                                              → ok
forge test --no-match-test "vm.ffi"                      → 410 passed, 0 failed, 1 skipped
forge test --match-path test/keeper/HyperCoreAdapterC2.t.sol   → 2/2
forge test --match-path test/keeper/StrategyExecutorH3.t.sol    → 6/6
forge test --match-path test/signals/SignalRegistryH4.t.sol     → 2/2
forge test --match-path test/staking/ZENTStakingH2.t.sol        → 2/2
forge test --match-path test/vaults/BaseVaultPhantomNav.t.sol   → 10/10
forge test --match-path test/vaults/SpotVaultEmergencyH1.t.sol   → 2/2
node validate-tests.js                                    → 167 contracts+tests, 0 hard errors
npm audit (3 manifests)                                   → 0 vulnerabilities
```

---

## What is NOT in scope of this handoff

- **HyperEVM mainnet deploy execution** — deploy scripts are present (`DeploySpotStack.s.sol`, `DeploySpotVault.s.sol`, `FinalizeSpotVault.s.sol`, `MigrateToMultisig.s.sol`, `MainnetDeployVaults.s.sol`); awaiting RPC credentials + multisig signer setup.
- **Keeper live-fire against HyperEVM testnet** — keeper is wired and tested in CI; live-fire requires `HYPEREVM_TESTNET_RPC_URL` env vars and an authorised signer key, neither of which are committed.
- **Frontend lint debt in `zentory-app`** — the previous PR #288 landed Phase-1 hardening. Residual lint items (any-type cleanups, set-state-in-effect) are tracked separately.

---

## File map (auditor fast-path)

```
zentory-protocol/
├── contracts/
│   ├── src/
│   │   ├── airdrop/MerkleDistributor.sol         (sweep — typed error)
│   │   ├── fees/FeeDistributor.sol                (dust event field, CEI order)
│   │   ├── interfaces/IFeeDistributor.sol         (matching event sig)
│   │   ├── interfaces/IZENTStaking.sol            (unchanged this pass)
│   │   ├── keeper/HyperCoreAdapter.sol            (C-2 fix: reduce-only bypass on SizeTooSmall)
│   │   ├── keeper/StrategyExecutor.sol            (H-3 fixes: CEI nonce, expiry cap, close sz=0)
│   │   ├── signals/SignalRegistry.sol             (maxEpochSignals exposure)
│   │   ├── staking/ZENTStaking.sol                (drift clamp + event)
│   │   └── vaults/BaseVault.sol                   (claimFees try/catch, redeemEmergency pro-rata)
│   ├── test/
│   │   ├── crosslanguage/DigestParity.t.sol       (expiry fix)
│   │   ├── fees/FeeDistributor.t.sol              (dust assertion)
│   │   ├── keeper/HyperCoreAdapterC2.t.sol        (NEW)
│   │   ├── keeper/StrategyExecutorH3.t.sol        (NEW)
│   │   ├── script/RedeploySignalRegistry.t.sol    (prank-state hygiene)
│   │   ├── signals/SignalRegistryH4.t.sol         (NEW)
│   │   ├── staking/ZENTStakingH2.t.sol            (NEW)
│   │   ├── vaults/BaseVaultNavAndLeverage.t.sol   (rewrite to assert post-fix)
│   │   ├── vaults/BaseVaultPhantomNav.t.sol       (NEW)
│   │   └── vaults/SpotVaultEmergencyH1.t.sol      (NEW)
│   └── validate-tests.js                          (comprehensive forge-std/OZ stubs)
├── package.json                                   (next ^16.3.3)
├── package-lock.json                              (NEW)
├── contracts/package.json                         (OZ ^5.6.1)
├── contracts/package-lock.json                    (refreshed)
├── contracts/keeper/package.json                  (axios 1.20.0, vite 8.2.2, vitest 4.1.11, etc.)
└── contracts/keeper/package-lock.json             (refreshed)
```

---

*Generated as part of the 2026-Q3 audit refresh; superseded by the next refresh cycle.*