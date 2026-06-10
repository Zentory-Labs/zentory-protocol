# Key Management & Rotation — Operational Policy

*2026 re-scan response. Context: Immunefi's 6-year audit attributes ~76% of 2025 DeFi
losses to infrastructure/operational failures — leaked operator keys and access-control
mistakes — not code bugs (e.g. Volo ~$3.5M Apr-2026 via a leaked operator key, Purrlend
~$1.5M via a stolen role key). For a signed-keeper protocol, keys ARE the attack surface.
This doc is the standing policy; the external auditor receives it as prior work.*

## 1. Key inventory (one key = one job; never reuse across roles)

| Key | Holds | Blast radius if leaked | Where it lives |
|---|---|---|---|
| **Deployer EOA** | one-shot deploys; admin until M3 migration | grant/revoke every role (CRITICAL until M3) | local signer only; never in CI; retired to Safe at M3 |
| **authorizedSigner (GP engine)** | signs `TradeSignal`/`Rebalance` EIP-712 | submit exposure changes (bounded by per-vault limits + long/flat weight) | engine host env; KMS/hardware-backed for mainnet |
| **Keeper EOA(s)** | `KEEPER_ROLE` tx submission; oracle `UPDATER_ROLE` | submit (not forge) signed actions; push one oracle report (median-bounded) | Railway service env |
| **MedianOracle updaters (≥3 mainnet)** | `report()` | move ONE report — median unaffected by a minority | separate hosts/envs per updater |
| **SENDER / PROVIDER keys (testnet demo)** | arena submissions | testnet-only | Railway env |
| **GitHub PAT (recorder)** | Contents+PR write on `zentory-app` ONLY | forge ledger PRs (visible in git history; chain re-verifiable) | Railway recorder env |
| **KEEPER_API_KEY / CRON_SECRET (dApp)** | API auth | call gated testnet endpoints | Vercel env |

## 2. Standing rules
1. **Separation:** deployer ≠ signer ≠ keeper ≠ oracle updaters. Verified in code
   (constructor grants) and deploy scripts; do not collapse roles "temporarily".
2. **Scope:** keeper powers are rebalance/submit ONLY — no arbitrary call/transfer
   targets exist in `StrategyExecutor`/`SpotVault`. Keep it that way; any new privileged
   function must justify why the keeper (vs governance) holds it.
3. **Storage:** env-vars on the host platform (Railway/Vercel) are acceptable for
   testnet. **Mainnet:** authorizedSigner + any fund-adjacent key moves to KMS or a
   hardware-backed signer; admin = Gnosis Safe (M3), never an EOA.
4. **No keys in:** git (CI secret-scans enforce), logs (signers never log key material),
   OneDrive-synced paths (INFRA-1: workspace must move off OneDrive), chat/tickets.
5. **Chain pinning:** every writer asserts chain id before broadcasting (keeper TS F-03;
   engine `EXPECTED_CHAIN_ID` guards in oracle_pusher/signal_submitter; dApp mainnet
   kill on `recordTradeManual`).

## 3. Rotation procedure (per key)
- **authorizedSigner:** generate new key → fund nothing (it only signs) →
  `StrategyExecutor.setAuthorizedSigner(new)` from admin (Safe post-M3) → retire old.
  One transaction; no downtime (signals signed by the old key stop verifying instantly).
- **Keeper EOA:** generate → fund gas → `grantRole(KEEPER_ROLE,new)` →
  `revokeRole(KEEPER_ROLE,old)` → update service env → sweep residual gas.
- **MedianOracle updater:** `addUpdater(new)` FIRST, then `removeUpdater(old)` (the
  contract enforces the order — removal below quorum reverts).
- **GitHub PAT / API keys:** issue new → swap env → revoke old in the dashboard.
  PAT scope stays Contents+PR on `zentory-app` only.
- **Cadence:** rotate on personnel change, suspected exposure, or 6 months — whichever
  comes first. Record each rotation (date, key role, operator) in this file's changelog.

## 4. Compromise response
1. Pause: `StrategyExecutor.setPaused(true)` (GUARDIAN) and/or vault circuit breaker.
2. Rotate the affected key per §3 (oracle updaters: add-then-remove).
3. Audit on-chain actions taken by the key during the exposure window.
4. Post-mortem in `docs/reports/` before unpausing.

## 5. Known open items (tracked)
- **M3:** deployer EOA still holds `DEFAULT_ADMIN_ROLE` everywhere → Gnosis Safe
  migration (`MigrateToMultisig.s.sol`, needs 5 signers). THE production gate.
- **INFRA-1:** workspace on OneDrive → move + rotate testnet Alchemy key (operator).
- Historical leaked testnet deployer key (`0xdc42…`): rotated + scrubbed (F-01);
  re-verified clean in the 2026-06 re-scan (docs contain only tx hashes / grep patterns).

## Changelog
- 2026-06-10: policy created (2026 re-scan); engine chain-guards + MedianOracle
  rotation-order enforcement shipped same day.
