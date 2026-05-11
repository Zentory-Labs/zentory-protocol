# GitHub Settings Action Spec — `edgeza/ZentoryToken` and `edgeza/zentorylabs.com`

*This file is an operational checklist for the maintainer of the two GitHub repositories. Each item below is a manual action in GitHub UI or `gh` CLI. None of these can be applied by code; they are repo-level settings.*

**Why this matters:** the rating platform that produced our 56/100 score explicitly cites "absence of a project description or README" three times under Uniqueness. The local README is excellent, but the repo is **private**, the README is **untracked**, the GitHub `Description` is empty, no `Topics` are set, and the `Homepage` points to a Vercel preview. The rater cannot read what it cannot see.

This document tells you exactly what to change, in what order, and why.

---

## STEP 0 — Decision: make `ZentoryToken` public

The single highest-leverage change. Current state:

```
edgeza/ZentoryToken    →  isPrivate: true,  description: "",  topics: null,  homepage: zentory-token.vercel.app
edgeza/zentorylabs.com →  isPrivate: true,  description: "",  topics: null,  homepage: zentorylabs-com.vercel.app
```

**Recommendation:** make `edgeza/ZentoryToken` **public** before the next rating pass. Reasons:

- The Uniqueness 40 score is unfixable without it. Every other action in this file is downstream.
- The codebase already assumes public scrutiny: there is a `SECURITY.md`, an Immunefi setup doc ([`docs/IMMUNEFI_SETUP.md`](docs/IMMUNEFI_SETUP.md)), and a verification master plan ([`docs/plans/2026-04-25-001-verification-master-plan.md`](docs/plans/2026-04-25-001-verification-master-plan.md)). Audits require public source.
- Competitors with comparable Investment Thesis scores (Numerai, Hyperliquid, etc.) are all public-source.
- Smart contracts deployed to a public testnet are effectively decompilable. Hiding the README does not hide the protocol; it only hides the *story*.

**Risks to mitigate before going public:**

1. **Secrets audit.** Search history for `ALCHEMY_API_KEY`, `PRIVATE_KEY`, `STRIPE_*`, `SUPABASE_SERVICE_ROLE_KEY`. The exploration found embedded Alchemy keys in `test_alchemy.py`, `test_monitor_final.py`, `test_receipt.py`, and an embedded deployer key in `scripts/simulate-e2e.ps1`. **Rotate** these keys, then either delete the files or move the keys to env vars **before** flipping the repo public. If the keys are already in git history, also run `git filter-repo` or accept that they are rotated-and-burned.
2. **Internal docs review.** Skim [`docs/regulatory-memo.md`](docs/regulatory-memo.md), [`docs/BUYBACK_DESIGN.md`](docs/BUYBACK_DESIGN.md), [`docs/SECURITY_AUDIT_BRIEF.md`](docs/SECURITY_AUDIT_BRIEF.md) for anything you would not want a journalist quoting. These are currently fine to publish on a read of the summaries, but verify before the flip.
3. **`frontend-old/`** is deprecated per [`docs/roadmap/implementation-status.md`](docs/roadmap/implementation-status.md). Consider deleting it from the public branch (keep a tag/archive for history if you need it).

If you decide to keep `ZentoryToken` private, then everything below applies to the **marketing site** (`edgeza/zentorylabs.com`), and the marketing site has to carry every Uniqueness signal alone. That is doable but strictly harder — the rater explicitly looks for the repo.

### Action (gh CLI)

```
# DO THIS LAST, after the secrets audit and content rewrite are committed.
gh repo edit edgeza/ZentoryToken --visibility public --accept-visibility-change-consequences
```

---

## STEP 1 — Commit the new content

The new files this branch introduces are currently untracked or modified locally. **They must be committed and pushed** for the rater to see them, regardless of public/private status.

```
git add README.md STRATEGY.md COMPETITORS.md TEAM.md CONTRIBUTING.md GITHUB_SETTINGS.md
git status                          # verify the staged set
git commit -m "docs: public-facing rewrite for rater + investor evaluation"
git push origin main
```

If you decided to make the repo public, do `STEP 0` only **after** this push lands on `main`.

---

## STEP 2 — Repo `Description`

Set the GitHub "About" description (max ~350 chars).

```
gh repo edit edgeza/ZentoryToken \
  --description "Non-custodial Alpha Vaults + on-chain quant Signal Arena on HyperEVM. ERC-4626 vaults (zBTC/zETH/zSOL/zXRP/zHYPE), EIP-712 signed signals, Ghost Portfolio attribution, fixed-supply ZENT utility token. Solidity + Foundry + Hyperliquid."
```

Why this exact text: it is the literal sentence the rater will index. It contains the protocol category ("Alpha Vaults", "Signal Arena"), the chain ("HyperEVM"), the standards ("ERC-4626", "EIP-712"), the venue ("Hyperliquid"), the differentiator ("Ghost Portfolio"), and the token ("ZENT"). Every word is a search hit.

Apply the same treatment to the marketing repo:

```
gh repo edit edgeza/zentorylabs.com \
  --description "Marketing site for ZENTORY Labs — The Signal Arena on HyperEVM. Non-custodial Alpha Vaults, EIP-712 quant signals, Ghost Portfolio attribution, ZENT token. Next.js 16 + Tailwind + Supabase."
```

---

## STEP 3 — Topics

Topics drive GitHub search and ecosystem-page placement.

```
gh repo edit edgeza/ZentoryToken \
  --add-topic hyperevm \
  --add-topic hyperliquid \
  --add-topic defi \
  --add-topic erc-4626 \
  --add-topic vault \
  --add-topic quant \
  --add-topic on-chain-signals \
  --add-topic eip-712 \
  --add-topic copy-trading \
  --add-topic foundry \
  --add-topic solidity \
  --add-topic non-custodial \
  --add-topic alpha-vault \
  --add-topic signal-arena \
  --add-topic zentory
```

For the marketing repo:

```
gh repo edit edgeza/zentorylabs.com \
  --add-topic zentory \
  --add-topic hyperevm \
  --add-topic defi \
  --add-topic nextjs \
  --add-topic marketing-site
```

---

## STEP 4 — Homepage URL

Currently points to a `*.vercel.app` preview. Change both to the canonical brand domain.

```
gh repo edit edgeza/ZentoryToken    --homepage "https://zentorylabs.com"
gh repo edit edgeza/zentorylabs.com --homepage "https://zentorylabs.com"
```

---

## STEP 5 — Social preview image

GitHub renders a 1280×640 PNG when the repo is shared on Twitter/Slack/LinkedIn. An unset preview shows a generic GitHub card and tells the rater "no marketing investment."

**Action (manual; cannot be done via `gh`):**

1. Generate a 1280×640 PNG with: ZENTORY wordmark + tagline "The Signal Arena on HyperEVM" + a subtle gradient or shader background. Use [`zentorylabs.com/zentory_logo_dark.png`](../zentorylabs.com/zentory_logo_dark.png) and [`zentorylabs.com/zentory_logo_light.png`](../zentorylabs.com/zentory_logo_light.png) as source.
2. Upload at: `https://github.com/edgeza/ZentoryToken/settings` → Social preview → Upload an image.
3. Do the same for `edgeza/zentorylabs.com`.

If you don't have a designer cycle right now, use Figma's free `Open Graph Image` template and 5 minutes is enough.

---

## STEP 6 — README badge row

Add a badge row near the top of [`README.md`](README.md) once the repo is public and CI is running on `main`. Badges are the second thing a rater sees after the description.

Suggested set:

```
[![CI](https://github.com/edgeza/ZentoryToken/actions/workflows/ci.yml/badge.svg)](https://github.com/edgeza/ZentoryToken/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/edgeza/ZentoryToken)](LICENSE)
[![Solidity](https://img.shields.io/badge/solidity-0.8.28-363636.svg)](contracts/foundry.toml)
[![HyperEVM](https://img.shields.io/badge/chain-HyperEVM-blue.svg)](https://zentorylabs.com)
[![Twitter Follow](https://img.shields.io/twitter/follow/ZENTORYLabs?style=social)](https://twitter.com/ZENTORYLabs)
```

Insert immediately after the `# ZENTORY Protocol` H1 in the README. (Not committed in this round because they only render correctly once the repo is public and CI history exists.)

---

## STEP 7 — Pinned repositories on `edgeza`'s profile

GitHub orgs/users can pin up to 6 repos. Pin in this order on `https://github.com/edgeza`:

1. `ZentoryToken` (the protocol).
2. `zentorylabs.com` (the marketing site).
3. Any other public artifact in the brand (whitepaper repo if split out, engine repo if split out, etc.).

This is a manual action: `https://github.com/edgeza` → "Customize your pins."

---

## STEP 8 — GitHub Discussions

Turn on Discussions and seed it. Discussions show "active project" to scrapers more reliably than an empty Issues tab.

```
gh repo edit edgeza/ZentoryToken --enable-discussions
```

Then in the UI, create these starter threads in **Announcements** category:

1. **"Welcome to ZENTORY Protocol"** — paste a condensed version of `README.md` § Problem Novelty + Solution Differentiation.
2. **"Roadmap to mainnet Q4 2026"** — paste the pitch-deck slide 17 timeline.
3. **"How to verify everything we claim"** — link to `STRATEGY.md` §9 "How we ask to be evaluated."

---

## STEP 9 — `CODE_OF_CONDUCT.md`

Standard signal. Use the [Contributor Covenant v2.1](https://www.contributor-covenant.org/version/2/1/code_of_conduct.md) verbatim, replacing the contact email with `conduct@zentorylabs.com` (or `contact@zentorylabs.io` if you don't want a separate inbox).

Not blocking, but adds a low-cost professionalism signal.

---

## STEP 10 — Verify ownership on the rating platform

The rating report explicitly lists:

- `Repository edgeza/ZentoryToken` — **Unverified**
- `Project handle @zentorylabs` — **Unverified**

Both have to be claimed on the rating platform (whichever one issued the 56/100 — likely Tokenization Potential Value / "TPV" platform). Verification typically requires:

- Adding a meta tag or `.well-known/` file to `zentorylabs.com`, OR
- Signing a message with the project deployer wallet, OR
- Posting a tweet from `@ZENTORYLabs` with a verification code.

The exact mechanism is platform-specific. Whoever holds the platform login should complete this *after* `STEP 1` (so the rater sees the new content immediately on verification) and *before* triggering a re-rate.

---

## STEP 11 — Re-trigger rating

Once `STEP 0`–`STEP 10` are complete:

1. Wait 2–4 hours for GitHub search index to refresh (so topics appear).
2. Wait until the marketing site's new `/why` page (deployed by the `zentorylabs.com` repo updates) has propagated and is indexable.
3. Click "Re-rate" / "Refresh" on the rating platform.

Expected lift if all of A1–E2 land:

| Dimension | Before | Target after this round |
|---|---|---|
| Uniqueness | 40 | 75–85 |
| Social Presence | 20 | 40–60 (limited by tweet history depth) |
| Founders | 0 | Verified (binary flip) |
| Investment Thesis | 83 | 83–88 (small bump from clearer docs) |
| **Overall** | **56** | **75–82** |

The Social score will lag by 2–4 weeks regardless of effort, because the rater weighs **content history**, not just account existence.

---

## Order of operations (one-pager)

```
1. Audit & rotate secrets in ZentoryToken         ← blocking
2. Commit README, STRATEGY, COMPETITORS, TEAM,    ← this branch
   CONTRIBUTING, GITHUB_SETTINGS to main
3. Push to origin/main
4. Make ZentoryToken public (gh repo edit ... --visibility public)
5. Set Description, Topics, Homepage on both repos
6. Upload social-preview.png on both repos
7. Enable Discussions; seed 3 threads
8. Pin ZentoryToken + zentorylabs.com on edgeza profile
9. Add CODE_OF_CONDUCT.md
10. Verify repo + handle ownership on rating platform
11. Wait ~24h for indexing
12. Trigger re-rate
```

Steps 1–4 are the irreversible part of the sequence. Steps 5–9 are reversible UI changes you can iterate on freely. Step 10 is one-time.
