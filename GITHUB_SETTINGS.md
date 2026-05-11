# GitHub Settings — `Zentory-Labs` Organization

*Operational checklist for the four repos under the `Zentory-Labs` GitHub organization. Last updated: May 2026.*

---

## Pre-flight: secrets audit (mandatory before any repo goes public)

**Do this before anything else.** If a key is already in any public git history, it is burned — rotate it at the provider first, then scrub.

```powershell
# Run inside zentory-protocol/ (after the split, this is the local folder)
git grep -nE "0x[a-fA-F0-9]{64}|sk_live_|alch_|PRIVATE_KEY\s*="
```

Known files to check (from pre-split audit):

| File | Credential | Fix |
|---|---|---|
| `engine/tests/test_alchemy.py` | Alchemy key | Rotate → delete |
| `engine/tests/test_monitor_final.py` | Alchemy key | Rotate → delete |
| `engine/tests/test_receipt.py` | Alchemy key | Rotate → delete |
| `scripts/simulate-e2e.ps1` | Deployer private key | Rotate → scrub |

---

## After the split

The four repos after running `MIGRATION_PLAN.md`:

| Repo | Visibility | License | Local folder |
|---|---|---|---|
| `Zentory-Labs/zentory-protocol` | **Public** (flipped after audit) | BSL 1.1 | `zentory-protocol/` |
| `Zentory-Labs/zentory-app` | Public | AGPL-3.0 | `zentory-app/` |
| `Zentory-Labs/zentorylabs.com` | Public | MIT | `zentorylabs.com/` |
| `Zentory-Labs/zentory-engine` | **Private** | Proprietary | `zentory-engine/` |

---

## Settings to apply after the split (gh CLI)

These are all handled by `migrate_to_org.ps1`. Manual alternatives below.

### Description + Homepage + Topics

```bash
# zentory-protocol
gh repo edit Zentory-Labs/zentory-protocol \
  --description "ZENTORY Protocol — on-chain quant Signal Arena on HyperEVM. Non-custodial ERC-4626 Alpha Vaults, EIP-712 signed signals, ZENT-staked reputation, Ghost Portfolio attribution. Solidity + Foundry." \
  --homepage "https://zentorylabs.com" \
  --add-topic "defi" --add-topic "hyperevm" --add-topic "erc4626" \
  --add-topic "signals" --add-topic "vaults" --add-topic "solidity" \
  --add-topic "foundry" --add-topic "quant" --add-topic "attribution" \
  --add-topic "non-custodial" --add-topic "bsl" --add-topic "zentory"

# zentory-app
gh repo edit Zentory-Labs/zentory-app \
  --description "ZENTORY dApp — non-custodial Alpha Vaults + Signal Arena UI for HyperEVM. Source for app.zentorylabs.com." \
  --homepage "https://app.zentorylabs.com" \
  --add-topic "defi" --add-topic "hyperevm" --add-topic "nextjs" \
  --add-topic "wagmi" --add-topic "viem" --add-topic "erc4626" \
  --add-topic "dapp" --add-topic "web3"

# zentorylabs.com
gh repo edit Zentory-Labs/zentorylabs.com \
  --description "Marketing website for ZENTORY Protocol (zentorylabs.com)." \
  --homepage "https://zentorylabs.com" \
  --add-topic "nextjs" --add-topic "marketing" --add-topic "tailwindcss"
```

### Discussions (zentory-protocol only — seed threads manually in the GitHub UI)

```bash
gh api -X PATCH /repos/Zentory-Labs/zentory-protocol -f has_discussions=true
```

Seed 3 threads in the Announcements category:
1. **"Welcome to ZENTORY Protocol"** — paste the Problem Novelty + Solution Differentiation from README.
2. **"Roadmap to mainnet Q4 2026"** — paste the Status section from README.
3. **"How to verify everything we claim"** — link to `STRATEGY.md` §9 "How we ask to be evaluated."

### Social preview image (manual — github.com UI only)

Upload a 1280×640 PNG at:
- `github.com/Zentory-Labs/zentory-protocol/settings` → Social preview → Upload
- `github.com/Zentory-Labs/zentory-app/settings` → Social preview → Upload
- `github.com/Zentory-Labs/zentorylabs.com/settings` → Social preview → Upload

Suggested content: ZENTORY wordmark + "The Signal Arena on HyperEVM" + a subtle dark gradient. Use `zentorylabs.com/zentory_logo_dark.png` as a base.

### Pin repos on org profile (manual)

At `github.com/Zentory-Labs`, pin in order:
1. `zentory-protocol` — the trust layer
2. `zentory-app` — the dApp
3. `zentorylabs.com` — the marketing site

### Profile README for the org

Create `Zentory-Labs/.github` with a profile README at:
`https://github.com/Zentory-Labs/.github/edit/main/profile/README.md`

Suggested content:
```
# ZENTORY Labs

Building the verifiable signal market for HyperEVM.

- [Protocol](https://github.com/Zentory-Labs/zentory-protocol) — Solidity contracts, tests, deploy scripts (BSL 1.1)
- [dApp](https://github.com/Zentory-Labs/zentory-app) — UI for Alpha Vaults + Signal Arena (AGPL-3.0)
- [Marketing](https://github.com/Zentory-Labs/zentorylabs.com) — zentorylabs.com

The alpha-generating engine is proprietary and not published.
```

---

## Flipping zentory-protocol to public

**Do this only after the secrets audit comes back clean.**

```bash
gh repo edit Zentory-Labs/zentory-protocol --visibility public
```

This is the single highest-leverage action for the rating. Without it, the rater's scraper hits a 404 on every claim.

---

## Verifying ownership on the rating platform

The rating report listed:
- `Repository edgeza/ZentoryToken` — Unverified
- `@zentorylabs` — Unverified

After the split, update both to:
- `Repository Zentory-Labs/zentory-protocol`
- `@ZENTORYLabs` (canonical handle; X URL is case-insensitive)

Verification steps per the platform's docs (typically: add a meta tag to `zentorylabs.com`, or sign a message with the project deployer wallet, or post a tweet from `@ZENTORYLabs` with a verification code).

---

## After everything lands

Wait 24–72 hours for AI scrapers (GPTBot, ClaudeBot, PerplexityBot, the rating platform's own crawler) to re-index:
- `github.com/Zentory-Labs/zentory-protocol` (public)
- `zentorylabs.com/why` (deployed with new links)
- `zentorylabs.com/sitemap.xml`
- `zentorylabs.com/robots.txt`

Then trigger re-rate per `docs/comms/RERATE_CHECKLIST.md`.
