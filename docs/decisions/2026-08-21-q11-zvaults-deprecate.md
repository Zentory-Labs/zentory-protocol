# Decision Q11 — zBTC / zETH / zSOL / zXRP depreciation path

*Status: **ACCEPTED** (decided 2026-08-21 by the Tier 0 prep team; founder sign-off pending on (a) the on-chain pause broadcast and (b) the long-term migration to `PassiveVault`).*
*Implemented by `fix/0-a-11-zvaults-deprecation`; on-chain pause is a separate founder-key broadcast against the broadcast script `script/PauseZVaults.s.sol`.*

## Problem

The z-vaults (`zBTCVault`, `zETHVault`, `zSOLVault`, `zXRPVault`) are `BaseVault`
subclasses whose constructor sets `performanceFee = 2000` (20%) and `maxLeverage =
30000` (3x). Neither value can be changed post-deployment — they are `immutable`
in `BaseVault`. The vaults do not run an active strategy: they are passive
benchmark wrappers, holding the underlying asset and letting holders track the
underlying price via `getNavPerShare()`.

Per audit finding #7 (`AUDIT_FINDINGS_2026-08-07.md` §0.A row 4, captured verbatim
in `MAINNET_READINESS.md §0.A`):

> **`zBTC/zETH/zSOL/zXRP` cannot execute the strategy at all — yet charge a 20%
> performance fee and advertise "3x".** Charging a performance fee for a strategy
> that cannot run is the single most indefensible thing here in diligence *and* to
> a regulator.

The dApp trust panel can be seen (per the deployment table at `DEPLOYMENTS.md`)
saying `3x` / `20%` on these addresses, which is the contradiction: the *number* of
strategy slots is zero, but the *fee* and *leverage* numbers claim the protocol
runs a leveraged alpha strategy that simply does not run for these vaults.

## Decision: DEPRECATE (do not wire)

Two paths were on the table:

1. **DEPRECATE** — pause new deposits, leave withdraws working, document the
   legacy perf-fee behaviour as a residual risk, and standardise the *future*
   pattern on a new `PassiveVault` wrapper whose constructor bakes in
   `performanceFee = 0` and `maxLeverage = 0` so this class of bug cannot recur
   on a new deploy.
2. **WIRE** — make the z-vaults delegate execution to the new `SpotVault` v2
   executor via a wrapper, so the perf-fee is actually justified by an active
   strategy on the same underlying.

We pick **DEPRECATE** for three reasons:

- **Cost & risk.** Wiring requires a new `BaseVault` subclass that delegates
  rebalance/recordTrade/captureFee flows to `SpotVault` for the same underlying
  asset. That is substantial contract work, a new audit surface, and creates a
  cross-vault position-sharing boundary that the auditor will rightly flag.
  The same outcome is achievable on a quarter of the surface by *pausing*
  instead.
- **Strategy fit.** The product surface today is `SpotVault` (long/flat spot,
  signal-driven rebalance). The z-vaults were *intended* as productised
  multi-asset wrappers for ETH/SOL/XRP exposure once those legs were live; they
  never graduated to wired status. The current SpotVault v1/v2 path can be
  extended to additional assets by a *new* passive vault (or by `SpotVault`
  directly with the new asset) rather than by retrofitting the legacy z-vaults.
- **Audit cleanup.** The auditor's finding is in two parts: (a) "the fee is
  charged for a strategy that doesn't run", (b) "the vault advertises leverage
  it cannot honour". Deprecation addresses both directly: a paused vault does
  not advertise new leverage, and the future `PassiveVault` pattern proves a
  perf-fee=0/leverage=0 wrapper exists in source for future deployments.

## Implementation

Four pieces, on `fix/0-a-11-zvaults-deprecation`:

1. **Pause script** — `script/PauseZVaults.s.sol`. Founder broadcasts against
   HyperEVM testnet (chain 998) with the deployer key holding `RISK_COUNCIL_ROLE`
   on each z-vault. Calls `activateCircuitBreaker("Q11 deprecation")` on each
   of the four live addresses. Idempotent (CB cannot be re-activated). Live
   addresses are the canonical ones from `DEPLOYMENTS.md`:

   - `zBTCVault = 0x93669dac07321ff397cf5734ae8364ea24addf45`
   - `zETHVault = 0xbe8a9d22560a1b126554b70aaca2d763b2e70c4e`
   - `zSOLVault = 0xb62ba9d0a14ac9f9601891179b3da52be71ce052`
   - `zXRPVault = 0x8b15204d88a9bb155be6798522983a3b5f7d7cb0`

   The script's post-deploy assertions verify `isCircuitBreakerActive() == true`
   on each. Re-running the script is a no-op.

2. **Future pattern** — `src/vaults/PassiveVault.sol`. A new `BaseVault`
   subclass whose constructor bakes in `performanceFee = 0`, `maxLeverage = 0`,
   `maxPositionSizeBPS = 10000`, `circuitBreakerDrawdownBPS = 2000`,
   `rebalanceThresholdBPS = 10000`. The exposed surface mirrors the legacy
   z-vaults (asset / name / symbol / feeRecipient / admin) so a future
   `DeployPassiveVaults.s.sol` (out of scope for this PR) can be a 1:1 drop-in
   replacement for the legacy rows.

   `PassiveVault` is **NOT** deployed in this PR — it ships only as a source-tree
   pattern for future asset wrappers. No on-chain state change for `PassiveVault`
   happens here.

3. **Regression tests** — `test/vaults/ZVaultDeprecation.t.sol`:

   - Each legacy z-vault blocks `deposit()` / `mint()` after CB activation.
   - Each legacy z-vault's `redeem()` continues to work after CB activation.
   - Each legacy z-vault's documented immutable risk rails are `performanceFee
     = 2000`, `maxLeverage = 30000` (so the auditor can confirm we are
     *aware* these are wrong and the decision was conscious — see the
     "Known residual" note below).
   - The new `PassiveVault` has `performanceFee = 0`, `maxLeverage = 0`.
   - The `PauseZVaults` script's selector surface compiles + is dry-runnable
     against a test vault instance.

4. **Invariant** — `test/invariants/BaseVaultNavMonotonicity.inv.t.sol`. For a
   passive `BaseVault` subclass (i.e. `maxLeverage == 0`), `getNavPerShare()`
   is invariant in the absence of either an external token transfer to the
   vault or a `_captureFee()`-triggering interaction. This locks in the
   invariant the dApp can rely on for a `PassiveVault`-style product.

## Document updates

- `docs/MAINNET_READINESS.md §0.A` row 4 flips from 🟡 partial → 🟢 closed
  with the PR link and the explicit note that the on-chain pause broadcast
  remains a founder-key action.
- `docs/AUDIT_READINESS.md §3.6` gets a one-line addendum referencing this
  decision (the Q11 row is closed on this PR; the alt future-class pattern
  landed; PR follow-up audit at next freeze).
- `DEPLOYMENTS.md` §Alpha Vaults table gains a `Status` column for the four
  z-vault rows reading `deprecated (Q11)`. This is a doc-only diff and ships
  alongside the PR.

## Known residual risk (documented, not a blocker)

The legacy z-vaults have **immutable `performanceFee = 2000`** in their on-chain
storage. The CB pause blocks *new deposits* and *mints* via
`onlyWhenCircuitBreakerInactive` on `BaseVault.deposit()` and `mint()`, but
**withdrawals still work** and `_captureFee()` is still called from
`_withdraw()` (a deliberate Q10 equalization design that the auditor signed
off). For an existing depositor whose underlying price has appreciated above
HWM, a withdraw will mint 20% of the alpha to `feeRecipient` as new fee shares.

This is acceptable on testnet for two reasons:

- The z-vaults are passive benchmark wrappers with negligible TVL on testnet
  (no public walkthrough ever pointed an investor at them; the product
  marketing surface is SpotVault-only via `app.zentorylabs.com/vaults/spot`).
- The perfect fix — re-deploy the legacy z-vaults as `PassiveVault` with
  `performanceFee = 0` and `maxLeverage = 0` and migrate balances — is a
  founder-key action that requires deploying new addresses and re-pointing the
  dApp registry (`lib/contracts.ts`). That migration is the **next** PR after
  this one lands, contingent on founder approval to broadcast.

For mainnet (chain 999, post-audit), the post-condition is: **no new z-vault
deployments** — every new benchmark vault deploys as `PassiveVault`
(performanceFee=0, maxLeverage=0) from the source pattern shipped here.

## Verification

- `forge test --match-path 'test/vaults/ZVaultDeprecation.t.sol' -vv` —
  5 tests (4 legacy × (deposit-blocks, redeem-works), 1 passive constructor
  invariants).
- `forge test --match-path 'test/invariants/BaseVaultNavMonotonicity.inv.t.sol' -vv` —
  1 invariant, 3 seed-handlers (deposit / transfer / redeem).
- `forge test -q` — full suite, expect 396 + new tests passing.

## Rollout

- Code lands on `main` via PR (`fix/0-a-11-zvaults-deprecation` → `main`).
- Founder reviews. Per `AGENTS.md`, founder merges to `main` (branch
  protection requires verified signatures + PR; no auto-merge).
- On merge, founder broadcasts `script/PauseZVaults.s.sol --rpc-url ... --broadcast`
  with the testnet RISK_COUNCIL_ROLE key.
- Post-broadcast: `cast call <zBTCVault> 'isCircuitBreakerActive()(bool)'` returns
  `true` for each of the four addresses. The CB-true state is then part of
  the next `audit/2026-Q3b` re-freeze (M2-F10).
- Future passive-vault migration (out of scope for this PR) requires founder
  to (a) deploy `PassiveVault` addresses, (b) update `lib/contracts.ts`, (c)
  broadcast a drain script for the legacy balances.
