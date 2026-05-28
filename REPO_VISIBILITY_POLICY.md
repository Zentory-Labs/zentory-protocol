# Repo Visibility — public, private, and why

The short answer to "should we make the repos private to protect our IP?":
**No — not the contracts and not the dApp.** The defensibility of ZENTORY
does not live in code visibility; it lives in the *license*, the *private
strategy engine*, and the *forward on-chain track record* that nobody can
clone. Making the public repos private would *destroy* trust and *not*
protect what actually matters.

This doc is the canonical policy.

---

## The decision, per repo

| Repo | Visibility | License | Why |
|---|---|---|---|
| `zentory-protocol` | **PUBLIC** | BSL 1.1 | Contracts MUST be public for any institutional LP to deposit. Verifiability is the moat, not the secret. BSL prevents commercial forks for the license term — that *is* the IP shield. |
| `zentory-app` | **PUBLIC** | AGPL-3.0 | Frontend is non-defensible regardless; public is the crypto norm and lets users audit their own client. AGPL forces any fork that runs as a service to open-source. |
| `zentorylabs.com` | **PUBLIC** | MIT | Marketing site. Public by purpose. |
| `zentory-engine` | **PRIVATE FOREVER** | Proprietary | The strategy generator IS the moat. Same model as Numerai: public scoring + private model weights. **Never make public.** |
| `zentory_algo` (local research sandbox) | **LOCAL ONLY, NEVER PUSH** | n/a | Walk-forward studies, parquet data, vendored-ensemble dev, tearsheets. No git remote. Should never have one. If a remote ever gets added: only `Zentory-Labs` private. |

---

## Why public-by-default is *correct* for DeFi (the counter-intuitive part)

The instinct "we're early, hide the code" is wrong for this category. Here's why:

1. **The contracts hold custody. People deposit only if they can READ THE CODE.**
   Closed-source DeFi vaults have been a "no" since FTX. An LP doing
   serious diligence will refuse to deposit into contracts they can't audit
   themselves; an auditor's report alone is insufficient for the
   sophisticated end of the market.
2. **The license is the IP protection — not visibility.** Uniswap v2/v3
   shipped under BSL precisely because BSL solves the "but won't someone
   clone us" worry without sacrificing trust:
   - BSL = source-available, free to read/study/audit.
   - BSL = **forbids commercial competing use** for the licence term (we
     can set, e.g., 2–4 years).
   - After the term, it converts to GPL/MIT/Apache (our choice).
   - That is much stronger IP protection than "private repo" because
     "private repo" gives you no recourse if someone sees the deployed
     bytecode (which is public on-chain regardless) and rebuilds it.
3. **Anything that matters is on-chain anyway.** Bytecode is public. ABIs
   leak the moment you publish a Etherscan-verified contract. Hiding the
   GitHub repo doesn't hide the contracts; it just hides the comments,
   tests, and history a serious reviewer wants.
4. **Investors discount you if your contracts are private.** Tier-1 crypto
   VCs (Paradigm, a16z, Variant) treat closed-source contracts as a red
   flag in 2026. You get worse terms, not better protection.
5. **What's actually defensible is not the code:**
   - **The signal generator** (`zentory-engine`) — already private. The
     strategy IP. The model.
   - **The on-chain track record** — forward, immutable, *impossible to
     clone* once it accumulates. Numerai's moat after 8 years isn't its
     scoring contract; it's the data network and reputation.
   - **The brand, team, and network effects** — none of which live in code.
   - **Audited + battle-tested deployed contracts with real TVL** —
     a fork of your repo gets none of that.

---

## What *must* stay private

These items are NOT code — they're operational and competitive:

- **Operational secrets** — keys, env vars, deploy keys, DB credentials,
  RPC URLs, Sentry DSNs, Vercel tokens, Railway tokens. Currently on
  OneDrive (audit F-02 finding). Move to **1Password** or **AWS Secrets
  Manager**. Never commit. `.gitignore` is necessary but not sufficient
  — also enable Secret Scanning + Push Protection (see SECURITY_HARDENING.md §3).
- **Strategy engine** (`zentory-engine`) — already private. Keep it that
  way. The vendored ensemble code in `src/strategy/ensemble.py` has
  byte-for-byte parity with the research engine; the research files
  themselves stay local in `zentory_algo`.
- **Pitch deck with cap-table / valuation slides** — don't commit to the
  public marketing site. Distribute via Docsend or a private channel.
- **Founder personal info** — KYC docs, personal addresses, tax info.
  Not in any repo ever.
- **Customer data** — when you have any: KYC, wallet-linkage, tester
  emails. Live in Supabase (paid tier, access-controlled), not a repo.
- **Internal strategy research, walk-forward results, parameter studies** —
  these are in `zentory_algo` (local) and `zentory-engine` (private). Fine.
- **Pre-disclosure security findings** — handle via `SECURITY.md` + Immunefi,
  never as public issues.

---

## What's *also* defensible without being secret

- **First-mover deployed track record** on HyperEVM testnet then mainnet.
- **Audit reports** (publish them — investors *want* to see them).
- **The dApp at app.zentorylabs.com** — visible product, hard to replicate
  the polish + integration trust quickly.
- **The Hyperliquid partnership brief / co-marketing relationship.**
- **The team's named reputation** post-launch.

---

## What about competitors?

A competitor copying the code today gets:
- A non-trivial Solidity project they have to understand and audit themselves.
- Zero protocol revenue, zero TVL, zero track record.
- A BSL violation if they deploy it commercially during the license term.
- Still no strategy engine — that's the actual product.

In practice, no serious team will fork this. The lazy ones can't operate it
profitably; the serious ones already have their own ideas. The single
biggest competitive risk is **us not shipping fast enough**, not anyone
forking us.

---

## Verdict

**Keep the three public repos public.** They are public for the right reasons
and protected by the right mechanisms (BSL/AGPL + the hardening in
`SECURITY_HARDENING.md`). The protection of ZENTORY's value comes from:

1. The **private engine** (the strategy moat).
2. The **license** on the public code (legal moat).
3. The **forward on-chain track record** that nobody can backfill (network moat).
4. **Operational hygiene** (secrets out of repos, multisig, paid infra,
   audit, bounty — see `GO_TO_MARKET.md`).
5. The **team's execution speed** to first real TVL before anyone else.

Making any of `protocol` / `app` / `marketing` private would *cost* trust,
investor confidence, and audit-readiness — and *gain* nothing meaningful
that the license + private engine don't already secure.

If a specific concern arises (e.g. a v2 redesign in progress that you don't
want disclosed yet), use a **private fork in the same org** for the WIP and
only merge to the public repo when it's audit-ready. That's standard.
