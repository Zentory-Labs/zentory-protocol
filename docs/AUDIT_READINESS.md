# Zentory Protocol — External-Audit Readiness Package

*Prepared for audit-firm scoping. Every claim below is verified against the
contents of this repository at the time of writing. Where a number could not be
reproduced live in the authoring environment, that is stated explicitly rather
than estimated.*

- **Repository:** `zentory-protocol` (public)
- **Contracts root:** `contracts/`
- **Solidity:** `0.8.28`, `via_ir = true`, `optimizer_runs = 200` (see `contracts/foundry.toml`)
- **Primary dependency:** OpenZeppelin Contracts 5.x (`contracts/lib/openzeppelin-contracts`, audited upstream)
- **Target chain:** HyperEVM mainnet (chain id `999`), pending this audit. Currently testnet-only on HyperEVM testnet (chain id `998`).
- **Companion docs in-repo:** `docs/SECURITY_AUDIT_BRIEF.md` (scope + threat model), `docs/AUDIT_OUTREACH.md` (firm outreach playbook), `docs/reports/pentest-2026-04-26.md`, `docs/reports/slither-2026-04-26.json`.

---

## 1. Contract inventory

All paths are relative to `contracts/src/`. Line counts (LOC) are the raw
`wc -l` of each file at authoring time. Domains follow the brief's grouping;
contracts present in the tree but outside the brief's named list are included
under the closest domain and flagged.

### Token

| Contract | File | LOC | Purpose |
|---|---|---:|---|
| `ZENT` | `ZENT.sol` | 68 | Fixed-supply (1B, 18 dec) ERC-20 governance token (`ERC20Votes` + `ERC20Permit`); mainnet has no admin mint — a one-shot `mintForTestnet` is gated to chain id 998 only. |
| `ZENTVesting` | `ZENTVesting.sol` | 170 | Linear-with-cliff vesting for team/investor allocations; tokens pre-deposited, beneficiaries claim after cliff. |
| `ProtocolTreasury` | `ProtocolTreasury.sol` | 56 | Central fee sink; permissionless `sweep` splits any token 50% → buyback, 50% → operations; owner-only `rescue` for misrouted assets. *(Not in brief's named list; token-domain treasury.)* |
| `ZENTBuyback` | `ZENTBuyback.sol` | 75 | Accumulates USDC from fees, (production) swaps to ZENT and burns to `0x…dEaD`; non-discretionary execution. *(Not in brief's named list.)* |
| `MerkleDistributor` | `airdrop/MerkleDistributor.sol` | 143 | Pull-based airdrop claim against a Merkle root (Uniswap/1inch-style, double-hashed leaves). *(Not in brief's named list; airdrop domain.)* |
| `IZENT` | `interfaces/IZENT.sol` | 17 | ZENT token interface. |

### Vaults

| Contract | File | LOC | Purpose |
|---|---|---:|---|
| `BaseVault` | `vaults/BaseVault.sol` | 304 | Abstract ERC-4626 benchmark-denominated vault; performance fee charged only on alpha above HODL high-water mark; immutable risk rails (maxLeverage, maxPositionSizeBPS, circuitBreakerDrawdownBPS, rebalanceThresholdBPS); `KEEPER_ROLE` / `RISK_COUNCIL_ROLE`. Not deployed directly. |
| `SpotVault` | `vaults/SpotVault.sol` | 250 | ERC-4626 vault denominated in the underlying; long/flat spot strategy, NAV valued via oracle; rebalances on signed signals. (Production target; currently exercised via the testnet shadow stack — see §2.) |
| `zBTCVault` | `vaults/zBTCVault.sol` | 24 | `BaseVault` wrapper for WBTC (3x max lev, 100% max pos, 20% DD breaker, 20% perf fee). |
| `zETHVault` | `vaults/zETHVault.sol` | 13 | `BaseVault` wrapper tracking ETH. |
| `zSOLVault` | `vaults/zSOLVault.sol` | 13 | `BaseVault` wrapper tracking SOL. |
| `zXRPVault` | `vaults/zXRPVault.sol` | 13 | `BaseVault` wrapper tracking XRP. |
| `IVault` | `vaults/IVault.sol` | 48 | Interface for the benchmark-denominated ERC-4626 vaults. |

### Signals

| Contract | File | LOC | Purpose |
|---|---|---:|---|
| `SignalRegistry` | `signals/SignalRegistry.sol` | 421 | Canonical append-only log of EIP-712-signed provider signals; anyone may relay a signed signal; status transitions via `resolveSignals()`. |
| `EpochScoring` | `signals/EpochScoring.sol` | 649 | Scores provider signals at epoch boundaries (Chainlink Automation), drives `ZENTStaking.slash()`/`reward()` via a Numerai-style clipped payout. |
| `SubscriptionVault` | `signals/SubscriptionVault.sol` | 374 | ERC-721 subscription NFT for signal-network access; ZENT-paid BASIC/PRO/ELITE tiers with expiry + prorated cancellation. |
| `SignalTypes` | `signals/SignalTypes.sol` | 99 | Shared library: asset-class registry, signal status enum, canonical signal struct/types. |
| `ISignalRegistry` | `interfaces/ISignalRegistry.sol` | 97 | SignalRegistry interface. |

### Staking

| Contract | File | LOC | Purpose |
|---|---|---:|---|
| `ZENTStaking` | `staking/ZENTStaking.sol` | 273 | Locks ZENT (7–730 days) for vault access and time-decayed governance weight (veBalance); one position per address; no early withdrawal. |
| `ModelBonding` | `staking/ModelBonding.sol` | 183 | Strategy providers bond ZENT as skin-in-the-game; `RISK_COUNCIL_ROLE` can slash to the insurance fund; unbond cooldown keeps capital slashable. |
| `IZENTStaking` | `interfaces/IZENTStaking.sol` | 65 | Staking interface. |

### Governance

| Contract | File | LOC | Purpose |
|---|---|---:|---|
| `Timelock` | `governance/Timelock.sol` | 19 | Thin wrapper around OpenZeppelin `TimelockController` (48-hour delay on execution). |
| `Zentroller` | `governance/Zentroller.sol` | 17 | Linkage contract resolving the canonical `ZENTStaking` address for voting-weight queries; decouples the Governor from the staking implementation. |
| `ZentGovernor` | `governance/ZentGovernor.sol` | 196 | ZENT-holder governance over risk params/treasury/upgrades; voting weight = `ZENTStaking.veBalance` (not raw balance); executes through the Timelock. |

### Keeper

| Contract | File | LOC | Purpose |
|---|---|---:|---|
| `StrategyExecutor` | `keeper/StrategyExecutor.sol` | 407 | Permissioned keeper validating EIP-712-signed GP-engine trade signals and executing via the adapter; mandate-bounded by per-vault `maxPositionSize` / `maxLeverageBPS`; `KEEPER_ROLE` / `GUARDIAN_ROLE` (pause) / `GOVERNOR_ROLE`; per-vault nonce replay protection. |
| `HyperCoreAdapter` | `keeper/HyperCoreAdapter.sol` | 240 | Sends order actions to HyperCore via the CoreWriter precompile (`0x3333…3333`); `EXECUTOR_ROLE`-gated order path (granted to `StrategyExecutor`). |

### Fees

| Contract | File | LOC | Purpose |
|---|---|---:|---|
| `FeeDistributor` | `fees/FeeDistributor.sol` | 187 | Routes performance fees per the whitepaper §6.4 split — 50% buyback, 25% Protocol Treasury, 15% insurance, 10% ops/GP engine; permissionless accumulate/distribute, governor-gated buyback trigger. One instance per vault. |
| `IFeeDistributor` | `interfaces/IFeeDistributor.sol` | 30 | FeeDistributor interface. |

**In-scope source total:** 27 `.sol` files under `contracts/src/` (excluding the
3 shadow contracts in §2). Non-interface, non-shadow implementation contracts
account for the bulk of the auditable surface; the largest single contracts are
`EpochScoring` (649), `SignalRegistry` (421), `StrategyExecutor` (407),
`SubscriptionVault` (374), `BaseVault` (304), `ZENTStaking` (273), and
`SpotVault` (250).

---

## 2. In-scope vs out-of-scope

### In scope

All contracts in §1 — i.e. everything under `contracts/src/` **except** the
shadow stack and test mocks listed below.

### Explicitly OUT of scope — TESTNET-ONLY, never deployed to mainnet

The following contracts under `contracts/src/shadow/` are a self-contained
testnet harness that lets the full SpotVault loop (deposit → signal-driven
rebalance → NAV moves with PnL → redeem) run end-to-end on HyperEVM testnet
**without** a real Hyperliquid spot integration. **None of these ship to
mainnet.** Each file carries an in-source `!!! NOT FOR MAINNET` banner.

| Contract | File | LOC | Why excluded |
|---|---|---:|---|
| `ShadowUSDC` | `shadow/ShadowUSDC.sol` | 17 | Mock 6-dec USDC with an open public `mint`. Replaced by real USDC in production. |
| `ShadowPriceOracle` | `shadow/ShadowPriceOracle.sol` | 58 | Push-updated Chainlink-compatible feed for demos; replaced by a real Chainlink feed on HyperEVM. Self-labeled "NOT AUDITED FOR PRODUCTION VALUE-FLOW." |
| `ShadowSpotAdapter` | `shadow/ShadowSpotAdapter.sol` | 103 | Testnet swap venue filling at oracle price minus configurable slippage; replaced by a CoreWriter-routed Hyperliquid spot adapter (which must itself be audited) in production. |

Additionally out of scope:

- **Test mocks**, e.g. `contracts/test/invariants/mocks/MockERC20.sol`, and the
  per-vault testnet `MockERC20` underlyings referenced in `DEPLOYMENTS.md`.
  These exist only for the test suite and testnet provisioning.
- **`contracts/lib/**`** (OpenZeppelin, forge-std) — audited/third-party upstream.
- **Off-chain components** — the keeper (`contracts/keeper/`, TypeScript), the
  Python research engine (separate `zentory-engine` repo), and the dApp
  (separate `zentory-app` repo). The Hyperliquid L1 precompiles that
  `HyperCoreAdapter` writes to are external infrastructure, not Zentory code.

The production replacements for the shadow stack — real USDC, a real Chainlink
feed, and a CoreWriter spot adapter — are **not yet in this repo** and will need
their own audit coverage once written. `DEPLOYMENTS.md` and the SpotVault
NatSpec both state this explicitly.

---

## 3. Security posture

### 3.1 Internal pentest — `docs/reports/pentest-2026-04-26.md`

A focused internal pentest (report dated 2026-04-27, supporting verification
gate G7) covered the contracts, the dApp, and the privileged keeper API.
Headline result:

| Severity | Count | Status |
|---|---:|---|
| Critical | 0 | Pass |
| High | 0 | Pass |
| Medium | 1 | Fixed |
| Low | 0 | Pass |

Method: 56 Foundry tests at the time, Slither (0 high/critical), and a live API
security test. Seven adversarial scenarios (P4.1–P4.7) were exercised and
documented: authorized-signer compromise, trade-signal front-running (nonce
replay), Timelock bypass, flash-loan governance (acknowledged — mitigated by
veZENT time-decay), keeper-key theft / guardian pause, vault circuit-breaker
bypass, and fee-recipient hijack. The single Medium (F-001, an unauthenticated
keeper API endpoint when `KEEPER_API_KEY` was unset) was fixed and verified.
F-002 (Slither `arbitrary-from` on `FeeDistributor.accumulate`) was
acknowledged as a false positive — the caller invariant is enforced by the
vault's AccessControl.

### 3.2 Internal full audit + spec-conformance re-audit

Two broader internal review passes preceded this readiness package:

- **Pre-mainnet audit (`AUDIT_REPORT.md`, 2026-05-26, workspace root):** a
  four-reviewer hostile-mode sweep across all repos. It returned a *do not ship*
  verdict with Solidity findings C-1/C-2 and H-1…H-7 (plus dApp/infra/narrative
  items out of this repo's contract scope). The contract-level findings from
  this pass are now reflected as fix markers in source — e.g. `SignalRegistry`
  carries the `Audit-finding C-2 fix` (epoch counter), `EpochScoring` carries
  `H-2`/`H-3` fixes (oracle stub and recency-bonus), `ZENTStaking` carries `H-4`
  (slash routed to the insurance fund), and the keeper carries `H-5`-class
  leverage/mandate hardening. Several Medium fixes are likewise annotated
  in-source (`ZENTVesting` M-6, `MerkleDistributor` M-8 double-hashed leaves,
  `ZENTBuyback` M-5 pull-everything removal, `ProtocolTreasury` M-7 rescue,
  `EpochScoring`/`SignalRegistry` M-1/M-2/M-4, `HyperCoreAdapter` L-2 access
  control on the order path).

- **Spec-conformance re-audit (`AUDIT_SPEC_CONFORMANCE.md`, workspace root):** a
  numeric re-audit. Its executive summary states 24 deviations
  (2 critical, 7 high, 9 medium, 5 low, 1 info before reviewer severity
  corrections); the finding table is numbered 1–26, with a de-duplication note
  explaining that a few entries share a root subsystem but are reported
  separately. Each finding is reproduced with a numeric trace. A prioritized
  subset has been
  fixed and merged, with explicit in-source markers
  `SECURITY FIX (spec-conformance audit, finding #N)` confirmable by grep:
  - **#1 (Critical)** `SubscriptionVault` — renewals now priced from the stored
    tier instead of a bitmap reverse-lookup that always resolved to ELITE
    (`SubscriptionVault.sol:173`, with `_getTierForBitmap` removed at `:355`).
  - **#2 (High)** `EpochScoring` — payout scale corrected so the
    `MAX_PENALTY_BPS`/`MAX_REWARD_BPS` clips actually bind
    (`EpochScoring.sol:431`).
  - **#3 (High)** `EpochScoring` — reference-close now snapshotted before
    scoring so accuracy is no longer identically zero (`EpochScoring.sol:274`).
  - **#4 (High)** `ZENTStaking` — `extendLock` now maintains `totalVeSupply`
    (`ZENTStaking.sol:139`).
  - **#9 (Medium)** `FeeDistributor` — the 25% slice now routes to the Protocol
    Treasury and 10% to ops/GP (`FeeDistributor.sol:100-120`).
  - **#20 (Low)** `EpochScoring` — recency-window off-by-one corrected
    (`EpochScoring.sol:545`).

  A separate post-disclosure fix (the 2026-05-31 A. Deev disclosure on the
  EpochScoring payout curve) is also annotated in source (`EpochScoring.sol:423`).

  **Honest caveat for the external auditor:** not all 26 deviations are
  closed. Lower-severity / testnet-bounded items remain open and documented —
  for example **#18** (`ZENT.CAP` is not re-checked as a ceiling in
  `mintForTestnet`; mainnet is unaffected because the mint is gated to chain id
  998 and is one-shot). The full finding list with reproductions and suggested
  fixes lives in `AUDIT_SPEC_CONFORMANCE.md` and should be handed to the auditor
  as prior work, not as a closed-out list.

### 3.3 Slither static analysis in CI

- **Workflow:** `.github/workflows/ci.yml` runs a dedicated `slither` job on
  every push/PR (`slither . --exclude-dependencies --filter-paths "lib"`,
  JSON report uploaded as an artifact). Slither is configured **advisory** —
  `continue-on-error: true`, so it never blocks the pipeline.
- **Config:** `contracts/slither.config.json` remaps `@openzeppelin`, filters
  `lib/` and `node_modules/`, and excludes a curated set of informational
  detectors (e.g. `timestamp`, `naming-convention`, `low-level-calls`,
  `assembly-usage`).
- The Foundry job in the same workflow runs `forge build --sizes`, the unit
  suite, and the invariant suite separately. A second per-package workflow
  (`contracts/.github/workflows/test.yml`) additionally enforces
  `forge fmt --check` and runs `forge test -vvv`.
- Committed Slither artifacts: `docs/reports/slither-2026-04-26.json` and
  `contracts/slither_report.json`.

### 3.4 Design-level mitigations (auditor-relevant invariants)

- **EIP-712 + per-vault nonce replay protection.** `SignalRegistry` is an
  `EIP712` domain with a typed `Signal` struct (`provider, assetClass, assetId,
  direction, confidence, nonce, expiresAt`). `StrategyExecutor` uses a domain
  separator bound to `block.chainid + address(this)`, a typed `TradeSignal`
  struct, and a per-vault `nonces` mapping; replay of a used nonce reverts
  (verified by the pentest P4.2 scenario and the keeper test suite).
- **Mandate-bounded executor.** `StrategyExecutor` enforces per-vault
  `maxPositionSize` and `maxLeverageBPS`; the authorized signer defaults to the
  deployer and must be explicitly transferred to the GP-engine key by
  governance ("no signals accepted" until then).
- **GUARDIAN_ROLE circuit breakers.** `StrategyExecutor` exposes a guardian
  pause that halts all execution; `BaseVault` carries an immutable
  `circuitBreakerDrawdownBPS` rail and an `isCircuitBreakerActive` flag that
  blocks deposits/mints and can only be deactivated by admin (pentest P4.5/P4.6).
- **Governance through Timelock.** `ZentGovernor` executes only via the 48-hour
  `TimelockController`; voting weight is vote-escrowed (`veBalance`), limiting
  flash-loan governance attacks by design (pentest P4.3/P4.4).
- **No mainnet admin mint.** `ZENT.mintForTestnet` reverts on any chain other
  than 998 and is one-shot.

---

## 4. Test coverage

> **Live run (2026-06-04):** `forge test` executed against `main` →
> **287 passed, 0 failed, 1 skipped** (288 total) across 28 suites, ~20s wall.
> This is an actual run, not a static count. The single skip is an intentional
> gated test. Re-run before freezing the audit branch and paste the fresh tail.

- **Latest live result:** **287 passed / 0 failed / 1 skipped** (2026-06-04, on `main`).
- **Static count:** **286+ test functions** across 28 test files under `contracts/test/`.
  To reproduce:
  ```bash
  cd contracts
  export PATH="$PATH:$HOME/.foundry/bin"
  forge test 2>&1 | tail -5
  ```

**Test directories (`contracts/test/`):**

| Directory | Focus |
|---|---|
| `test/` (root) | `ZENT`, `ZENTVesting`, `ZENTBuyback`, `DeployPipeline`, `EpochScoring.recencyEarlyEpochs` |
| `test/airdrop/` | `MerkleDistributor` |
| `test/crosslanguage/` | `DigestParity` (Solidity↔engine EIP-712 digest parity; auto-skips when the engine signer is absent) |
| `test/fees/` | `FeeDistributor` |
| `test/fuzz/` | `BaseVault.fuzz`, `StrategyExecutor.fuzz` |
| `test/governance/` | `ZentGovernor` |
| `test/integration/` | `SignalNetworkDeploy` |
| `test/invariants/` | `BaseVault.inv`, `StrategyExecutor.inv` (+ `mocks/MockERC20`) |
| `test/keeper/` | `StrategyExecutor` |
| `test/script/` | `MainnetDeployVaults` |
| `test/shadow/` | `ShadowStack` (testnet harness) |
| `test/signals/` | `EpochScoring`, `EpochScoringSnapshotOrder`, `PayoutCurve`, `SignalRegistry`, `SubscriptionVaultRenewal` |
| `test/staking/` | `ZENTStaking`, `ModelBonding` |
| `test/vaults/` | `BaseVault`, `SpotVault`, `VaultWrappers` |

The suite spans unit, fuzz (≥256 runs default, 1000 in CI), invariant, and
integration/deploy-pipeline tests. Several files exist specifically to lock in
audit fixes (`PayoutCurve`, `EpochScoringSnapshotOrder`,
`SubscriptionVaultRenewal`, `EpochScoring.recencyEarlyEpochs`).

---

## 5. Canonical testnet deployments

Source of truth: `DEPLOYMENTS.md` (kept in sync with the Foundry broadcast logs
under `contracts/broadcast/`). **HyperEVM testnet, chain id `998` — testnet
artifacts only, no economic value.** Mainnet (chain id `999`) addresses are
published only after this audit + the Q4 2026 mainnet gate.

### Token
| Contract | Address |
|---|---|
| `ZENT` | `0x271cd48c1297caccd810c7b1bcd904f459df7117` |
| `ZENTVesting` | `0xf7c45f45768d790f388215a44d6e01f6f2568774` |

### Alpha Vaults (ERC-4626)
| Vault | Address | Underlying (testnet mock) |
|---|---|---|
| `zBTCVault` | `0x93669dac07321ff397cf5734ae8364ea24addf45` | `0x80f727af3f7932718feb25fc28818ad103040bd2` |
| `zETHVault` | `0xbe8a9d22560a1b126554b70aaca2d763b2e70c4e` | `0x08890a5b7d6d157da65c04c19150ff7d124eae40` |
| `zSOLVault` | `0xb62ba9d0a14ac9f9601891179b3da52be71ce052` | `0xe1fe75622bd5d962c72c1d0a621e5fa6656a4371` |
| `zXRPVault` | `0x8b15204d88a9bb155be6798522983a3b5f7d7cb0` | `0x2b9d5bbd8c5fefc71e985d993c13db2770469972` |
| `zHYPEVault` | _not deployed (post-audit)_ | _native HYPE_ |

> `BaseVault.sol` is abstract and is not deployed directly.

### Staking & Bonding
| Contract | Address |
|---|---|
| `ZENTStaking` (veZENT) | `0x93A14D1c60e054038980965CF3CAa50CEB848de9` |
| `ModelBonding` | `0x15f6c4bf4000747e0fdd85b33998a36f5bdf5007` |

### Fee Distribution (one instance per vault)
| Distributor for | Address |
|---|---|
| zBTCVault | `0x8fb48f84aa69e89e0360e6d2d26c447aa57dcf73` |
| zETHVault | `0x403e8c79653b1cb7a5c0eaa313ec0c7d0cac7e2c` |
| zSOLVault | `0xc69f8a8014b4d17ee2e7457109ff1db33c0c7d7f` |
| zXRPVault | `0xe990bfbc5c1e5779cb54cb95150edbbb2c2800d0` |

### Governance
| Contract | Address |
|---|---|
| `Timelock` | `0x1504ca3c050c88ccca67696d642f634fc381fd03` |
| `Zentroller` | `0x24f9401284ce16cfe61e40c1f9e3fb37d15b878e` |
| `ZentGovernor` | `0x21ba1f7c028b1adc78e75ac187b08b1bdd567118` |

### Strategy Execution
| Contract | Address |
|---|---|
| `HyperCoreAdapter` | `0xdad9175f6d2da1709ba3f73711e69022538d21a7` |
| `StrategyExecutor` | `0xacd862ef134d772b0ca53a97f53ccdd00abc05cf` |

> `HyperCoreAdapter` and `StrategyExecutor` were re-deployed in Phase 5 to apply
> hardening fixes from the internal pentest; earlier broadcast addresses are
> deprecated.

### Signal Arena
| Contract | Address |
|---|---|
| `SignalRegistry` | `0xA71cfdA74fc0BB7bE3f95aB806197286549e82e7` |
| `EpochScoring` | `0x659569A6f195698745779E59fef88e3B5Fe0484A` |
| `SubscriptionVault` | `0xb053b9a1A82D57B2BEa7cC4a472924Fb6926933E` |

### Shadow Stack — testnet only (OUT OF SCOPE, see §2)
| Contract | Address |
|---|---|
| `SpotVault` | `0x504E998B32D165cfd6470a8a0000235550C33cBc` |
| `ShadowSpotAdapter` | `0x385Ba1f9A9d74A28974C8F6c03762D03B0e4a00c` |
| `ShadowPriceOracle` | `0x46a7c01424229CB5B2C9FF069e6b0eab07490Fd4` |
| `ShadowUSDC` | `0x2DF6A937da1430B4B593fE3EB2C9AB986cC3AF9e` |

To verify any address: look it up on `https://testnet.purrsec.com/address/<address>`
and compare on-chain bytecode against `forge inspect <Contract> bytecode`.

---

## 6. Audit vendor shortlist

> **All figures are 2026 ballpark estimates, not quotes.** They reflect public
> pricing norms and the team's own outreach notes (`docs/AUDIT_OUTREACH.md`) for
> a ~3.6k-LOC HyperEVM DeFi engagement. Get firm proposals before budgeting.

| Firm | Model | Rough cost (2026 est.) | Notes |
|---|---|---|---|
| **Spearbit / Cantina** *(team's top pick)* | Distributed researcher network; Cantina is the front-of-house intake for the same auditors | ~$80k–150k | Strong fit for DeFi infra at this size (1k–5k LOC); flexible solo/medium-scope engagements without long lead times; public-quality reports. Typical 4–8 weeks from kickoff, booking 4–8 weeks out. Apply via `cantina.xyz/welcome`. |
| **Trail of Bits** | Firm engagement, named senior team | ~$150k–300k+ | Strongest brand signal for institutional LPs / token listings; "gold standard" report for investor diligence. Longer waitlist (8–12 weeks) and pricier — keep as the premium-tier comparison rather than the default. |
| **OpenZeppelin** | Firm engagement | ~$100k–250k (scope-dependent) | Deep ERC-4626 / OZ-stack familiarity (the codebase is built on OZ 5.x), which can reduce wasted hours on standard components. Well-known report format; good for an OZ-heavy contract suite. |
| **Code4rena / Sherlock** | Competitive audit contest (pay-per-finding bounty pool) | ~$50k–100k pool | Broad-coverage sweep at lower, less-predictable cost; ~1–2 week active contest + ~2 weeks judging. Best run **after** a firm audit to backstop remediation (lots of eyes, minimal prep). |

**Suggested sequence** (consistent with `docs/AUDIT_OUTREACH.md`): run a primary
firm audit (Spearbit/Cantina or OpenZeppelin) → remediate → then a 1-week
Sherlock/Code4rena contest as a remediation backstop, with Trail of Bits held as
the premium comparison / v2-milestone option. When picking, weight sample-report
quality and ERC-4626 / signal-market domain experience above price (all four are
within budget).

**What firms will ask for, and where it lives:**

| Question | Answer in-repo |
|---|---|
| Frozen audit commit | `git rev-parse main` on a frozen `audit/2026-Qx-<firm>` branch |
| Scope + threat model | `docs/SECURITY_AUDIT_BRIEF.md` (§4 threat model) + §1–§2 above |
| Existing tests | 28 forge test suites / 287 passing, 0 failing, 1 skipped — live run 2026-06-04 (§4) |
| Static analysis history | `docs/reports/slither-2026-04-26.json`, CI slither job |
| Pentest history | `docs/reports/pentest-2026-04-26.md` |
| Prior internal audits | `AUDIT_REPORT.md`, `AUDIT_SPEC_CONFORMANCE.md` (workspace root) |
| External dependencies | OpenZeppelin Contracts 5.x (in scope as integrated; upstream audited), Hyperliquid L1 precompiles (out of scope) |

---

*This document is repo-derived and should be regenerated if the contract set,
test count, or deployment table changes. Live `forge test` output should be
pasted into §4 by a maintainer with a working Foundry toolchain before this
package is sent to a firm.*
