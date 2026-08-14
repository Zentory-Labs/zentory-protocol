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
  See §6 below for the non-OneDrive workflow.
- **INFRA-2 (2026-08-14, NEW):** the following files containing live credentials
  sit on the OneDrive-synced workspace and MUST be relocated + the keys rotated
  BEFORE mainnet:
  - `zentory-protocol/contracts/.env` — testnet deployer
    `PRIVATE_KEY=0x924ba663…3bfe8e55` (NOT in git; gitignored). Blast radius: any
    testnet contract re-deploy until `DEFAULT_ADMIN_ROLE` migrates to the Safe.
  - `zentory-app/.vercel/.env.production.local` — Vercel project env downloaded
    via `vercel env pull`, contains `NEXT_PUBLIC_SENTRY_DSN` and live
    `KEEPER_*` keys (NOT in git; `.vercel/` is gitignored). Blast radius:
    Sentry source-map upload (auth token present) + Vercel preview deploys.
  - Both files were confirmed NOT in any commit (`git log --all -p` returns
    empty); the exposure is sync-only, not history.
- Historical leaked testnet deployer key (`0xdc42…`): rotated + scrubbed (F-01);
  re-verified clean in the 2026-06 re-scan (docs contain only tx hashes / grep patterns).

## 6. Non-OneDrive workflow (INFRA-1 / INFRA-2)

The workspace currently lives under
`%USERPROFILE%\OneDrive\Documents\GitHub\ZENTORY LABS\…` and OneDrive syncs any
file placed in that tree — including `.env` files — to Microsoft's cloud and to
every other device signed in to the same account. **OneDrive sync is
incompatible with secret storage.** Apply both of the following:

### 6.1 Keep the code on OneDrive, but move every secret OUT
1. Pick a non-synced root for secrets. On Windows use
   `%LOCALAPPDATA%\zentory\` (e.g. `C:\Users\<you>\AppData\Local\zentory\`).
   This folder is NEVER synced.
2. Move the live `.env` files there:
   - `%LOCALAPPDATA%\zentory\zentory-protocol-contracts.env`
   - `%LOCALAPPDATA%\zentory\zentory-app-vercel.env`
3. Symlink them back if a tool insists on reading from the repo path:
   `mklink contracts\.env %LOCALAPPDATA%\zentory\zentory-protocol-contracts.env`
   (cmd, elevated). Prefer not symlinking — most tools accept an env var that
   points at the real path.
4. Add `OneDrive` to the deny list for `.env*` via OneDrive's "Manage Backup
   Folders" → "Stop backing up" for the workspace, or use
   `attrib +H contracts\.env` so OneDrive ignores it (hidden files are still
   synced by default; the cleaner fix is the non-synced root above).

### 6.2 Rotate every key that ever lived on OneDrive
For each secret that has been in a synced folder, treat it as exposed and
rotate per §3:
- Testnet deployer (`PRIVATE_KEY` in `contracts/.env`):
  1. Generate a fresh key (new ethers wallet or hardware signer).
  2. Call `StrategyExecutor.setAuthorizedSigner(new)` (admin) and
     `SpotVault.grantRole(KEEPER_ROLE, new)` then `revokeRole(KEEPER_ROLE, old)`
     once the new signer is wired in.
  3. Update `%LOCALAPPDATA%\zentory\zentory-protocol-contracts.env` and every
     Railway/Vercel env that references it.
  4. Append the rotation to §Changelog.
- Vercel `SENTRY_AUTH_TOKEN` / `KEEPER_*`:
  1. Regenerate at https://sentry.io/settings/auth-tokens/ and revoke the old.
  2. `vercel env rm SENTRY_AUTH_TOKEN production` then re-add via
     `vercel env add SENTRY_AUTH_TOKEN production` (Vercel CLI).
  3. Run `vercel env pull` from a non-OneDrive checkout if you need a local copy.

### 6.3 Pre-commit guard (so we never regress)
Add a `.git/hooks/pre-commit` hook that refuses to add any `.env*` file. The
existing `.gitignore` already excludes them, but the hook is a belt-and-braces
against an IDE auto-stage that bypasses `.gitignore`. Sample:
```sh
#!/bin/sh
git diff --cached --name-only | grep -E '(^|/)(\.env|\.env\.[a-z]+\.local)$' && {
  echo "Refusing to commit a .env file. Move it to %LOCALAPPDATA%\\zentory\\ first." >&2
  exit 1
}
```

## Changelog
- 2026-08-14 (P0-4): documented INFRA-2 exposure (PRIVATE_KEY + Sentry token on
  OneDrive) and §6 non-OneDrive workflow. Files confirmed NOT in git history.
  **Operator action pending: rotate keys per §6.2 and move files out of OneDrive.**
- 2026-06-10: policy created (2026 re-scan); engine chain-guards + MedianOracle
  rotation-order enforcement shipped same day.
