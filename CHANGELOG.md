# Changelog

All notable changes to the public ZENTORY Protocol repository are recorded here. This file follows the spirit of [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) but is grouped by week rather than semver releases — formal semver tags begin at mainnet (Q4 2026 gate).

Scope of this file: the public protocol layer only — smart contracts, deploy scripts, public docs, CI, the epoch-settlement keeper, the public-facing pieces of the testnet pipeline. **The internal research engine is in a private repository and is not represented here by design.**

---

## Unreleased

Nothing in flight on `main` beyond the entries below.

---

## 2026-05-12 — Repository structure, license, fee consistency

### Added

- [Business Source License 1.1](LICENSE) for the public protocol layer, with a Sept 30, 2030 conversion to GPL-3.0. Rationale and full text are in the `LICENSE` file and explained in the [Open Source Policy section of the README](README.md#open-source-policy).

### Changed

- Migrated the codebase from the personal `edgeza/ZentoryToken` monorepo to the [`Zentory-Labs`](https://github.com/Zentory-Labs) GitHub organization, split into four repositories with explicit licenses:
  - [`zentory-protocol`](https://github.com/Zentory-Labs/zentory-protocol) (this repo, **BSL 1.1**)
  - [`zentory-app`](https://github.com/Zentory-Labs/zentory-app) (dApp, **AGPL-3.0**)
  - [`zentorylabs.com`](https://github.com/Zentory-Labs/zentorylabs.com) (marketing, **MIT**, private repo, public deploy)
  - [`zentory-engine`](https://github.com/Zentory-Labs/zentory-engine) (research engine, **Proprietary**, private)
- Reorganised the README to lead with Problem Novelty, Ecosystem Position, and Solution Differentiation sections (a named-competitor capability matrix vs Numerai, Yearn, Beefy, eToro, Bitget Copy, dHEDGE, Polymarket, Telegram signal groups).
- Added a [`DEPLOYMENTS.md`](DEPLOYMENTS.md) canonical record of all live HyperEVM testnet contracts.

### Fixed

- Removed a stale Next.js whitepaper artifact in the protocol repo that quoted a pre-v2 **20%** performance fee. The canonical figure is **15%** of yield (see [`docs/whitepaper.md`](docs/whitepaper.md) §6), now consistent across every public surface.

---

## 2026-04-30 — Hardening week

### Security

- **Keeper key rotation.** The testnet epoch-settlement keeper was rotated to a fresh key; the previous key was revoked across all environments.
- **Stats hygiene.** Removed placeholder P&L data from the marketing surface and clarified that the testnet metrics on `zentorylabs.com` are testnet-only with no real economic value.

### Fixed

- Cron heartbeat route no longer pulls `node-fetch`; uses the Node 18+ built-in instead. Eliminates a runtime dependency that was easy to forget to keep current.

---

## 2026-04-29 — Vault-first positioning and Stripe removal

### Changed

- Reframed the marketing copy across all pages around the **Alpha Vault, Signal Arena, and Ghost Portfolio** triple — replacing the earlier generic "research / yield / discovery" framing.
- Replaced the dApp swap widget with a Vault Stats panel (read-only, sourced from on-chain reads), so the homepage now communicates "what the vault does" instead of "trade your token here."
- Production polish: removed emojis from production UI in favour of text labels and plain symbols (consistency, accessibility, screenshotability).

### Removed

- **Stripe integration is gone.** All subscription tiers are now paid in ZENT on-chain via [`SubscriptionVault.sol`](contracts/src/signals/SubscriptionVault.sol). Off-chain fiat rails are not part of the protocol.
- Removed dangling triangle-arrow icons in the contribute dashboard in favour of `+` / `-` semantics.

### Fixed

- Internal API path: `/api/provider` renamed to `/api/contribute` (existing readers and smoke tests updated to match).

---

## 2026-04-27 — Execution + indexing layer

### Added

- **StrategyExecutor on-chain log indexer.** Every accepted signal that is routed through [`StrategyExecutor.sol`](contracts/src/keeper/StrategyExecutor.sol) is now indexed off-chain into Supabase with row-level security policies enforcing per-vault read scoping. This is the data spine for the Ghost Portfolio.
- **Hybrid fills pipeline scaffolding.** End-to-end plumbing from Hyperliquid fill events into per-vault NAV accounting, with precision-preserving arithmetic. Design doc: [`docs/superpowers/specs/2026-04-27-hybrid-execution-metrics-design.md`](docs/superpowers/specs/2026-04-27-hybrid-execution-metrics-design.md).
- **Build verification surface:** `/api/version` endpoint returns the deployed git SHA, used to confirm the right code is live on the right environment.
- **Slither config + dead-code removal pass** across [`contracts/src/`](contracts/src). Slither runs in CI on every PR and any new warning blocks the merge.

### Changed

- HyperEVM RPC calls are now proxied through a server route rather than client-direct, so the public dApp does not expose RPC keys. ChainId is forced server-side to chain 998 (testnet) to prevent silent fallback to mainnet endpoints.
- `eth_getLogs` calls in the engine indexer are now chunked into 1000-block windows. Eliminates a class of "log range too wide" errors against HyperEVM testnet's RPC limits.

### Fixed

- Frontend viem reads now parse human-readable ABIs (regression introduced when the ABI generator was changed).
- `SimulateEndToEnd.s.sol` compile errors that were blocking CI on Foundry path. The script and its `console2` logs are now CI-clean.
- Admin fuzz test no longer trips on the (intentional) self-transfer edge case that has no security implication.

---

## 2026-04-26 — Foundation: cross-language digest parity, CI on Node 24

### Added

- **Python ↔ Solidity EIP-712 digest parity test** ([`contracts/test/crosslanguage/DigestParity.t.sol`](contracts/test/crosslanguage/DigestParity.t.sol) + [`engine/scripts/sign_trade_signal.py`](engine/scripts/sign_trade_signal.py)). The engine signer and the Solidity domain separator are now provably identical at every commit — the off-chain signer cannot produce a digest the on-chain verifier rejects, by construction.
- **Internal pentest record** at [`docs/reports/pentest-2026-04-26.md`](docs/reports/pentest-2026-04-26.md), with the static-analysis snapshot at [`contracts/slither_report.json`](contracts/slither_report.json).

### Changed

- CI opted into Node 24 with `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24` so the JavaScript action runtime matches what the keeper/indexer actually run on.

### Fixed

- All API responses now go through a `toSafeJson` wrapper that handles BigInt serialization for `viem`-typed values. Eliminates the silent 500s that were happening when a contract read returned a uint256.

---

## 2026-04-24 — Repository created

Initial commit of the ZENTORY Protocol monorepo (later split per the [2026-05-12 entry](#2026-05-12--repository-structure-license-fee-consistency)). See [`docs/plans/2026-04-24-001-feat-zent-protocol-build-plan.md`](docs/plans/2026-04-24-001-feat-zent-protocol-build-plan.md) for the seed build plan.

---

## Maintenance notes

- This file is updated by hand on every batch of substantive merges. Cosmetic, "update" or "up" commits are intentionally excluded.
- For the full per-commit history see `git log` or [GitHub commits](https://github.com/Zentory-Labs/zentory-protocol/commits/main).
- The internal research engine has its own private changelog. The public protocol does not depend on engine internals — only on the EIP-712 signed signals it emits, which are verifiable on-chain.
