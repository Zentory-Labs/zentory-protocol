# Zentory Labs — Public vs. Private Information Policy

**Owner:** Zentory Labs core team
**Status:** Active policy — last reviewed 2026-08-28
**Audience:** All contributors, contractors, advisors, agencies, and
third parties working with or on behalf of Zentory Labs.

This document is the authoritative classification for what is publicly
disclosable today, what must remain private, and what is time-phased
(made public later). It pairs with our incident-response runbook and
with the SECURITY.txt disclosure contacts.

If a piece of information is not listed below, ask before publishing it.
The default is **private until proven safe**.

---

## TL;DR (one-page matrix)

| Asset / Artefact                              | Status today                       | License                   | When made public                                       |
|-----------------------------------------------|------------------------------------|---------------------------|--------------------------------------------------------|
| ZENT token contract (`ZENT.sol`)              | **Public**                         | BUSL-1.1 (testnet copy)   | Already public (testnet)                               |
| Vault + signal contracts (`contracts/src/`)   | **Public (testnet deployment)**    | BUSL-1.1                  | Source public now; mainnet deployment post-audit       |
| Deploy scripts (`contracts/script/`)          | **Public**                         | BUSL-1.1                  | Already public                                         |
| Foundry tests (`contracts/test/`)            | **Public**                         | BUSL-1.1                  | Already public (no economic value)                     |
| Keeper JS (`contracts/keeper/`)              | **Public (interface only)**        | BUSL-1.1                  | Already public                                         |
| dApp frontend (`zentory-app`)                 | **Public**                         | AGPL-3.0                  | Already public                                         |
| Engine logic (`zentory-engine`)               | **Source-available, proprietary**  | Proprietary               | **Never** (the moat)                                   |
| Strategy parameters / model weights           | **Private — never commit**         | Proprietary               | **Never**                                              |
| Keeper live-fire env vars (`HYPEREVM_RPC_URL`, `KEEPER_PRIVATE_KEY`, etc.) | **Private — gitignored + env-only** | N/A                       | **Never**                                              |
| Supabase service-role keys                    | **Private — gitignored + Vault/Vercel-env** | N/A               | **Never**                                              |
| Telegram senders from Web3 security firms     | **Verify before acting**           | N/A                       | Document verification process before any commit / share |
| Treasury multisig addresses                   | **Private until TGE**              | N/A                       | TGE day -1 (pre-announced)                             |
| Real-user wallet addresses (any scale)        | **Private — anonymous by design**  | N/A                       | **Never** (no PII collected)                            |
| Whitepaper (tokenomics + protocol design)     | **Public**                         | (C) Zentory Labs          | Already public                                         |
| Pitch deck (investor-facing)                  | **Private**                        | (C) Zentory Labs          | NDA-required; never commit to public repo              |
| Investor KYC docs, signed NDAs                | **Private**                        | N/A                       | **Never** (not in any git tree)                         |

---

## 1. Why this policy exists

Three failure modes we are explicitly defending against:

1. **Operational secrets leak** — a private key, a service-role JWT, or a
   live RPC URL landing in a public repo. We have hit this twice (testnet
   deployer EOAs `0x3f07…` and `0xe56E…`); those addresses are documented
   as compromised and never reused, but the incident was painful.

2. **IP leak via "free" tooling** — a Telegram offer from a no-name
   security firm offering a "free Security Agent" turns out to be a code
   exfiltration pipeline, and now your proprietary strategy is on a
   competitor's server. Two of these offers arrived in the last week.

3. **Premature disclosure** — we ship a feature, blog it, and a competitor
   forks it before we've captured our first paying user. The strategy
   moat in `zentory-engine` is the single most important IP we hold. It
   stays private until we have revenue and patents (or trade-secret
   registration, depending on jurisdiction).

The default for any new artefact is: *can we show this to a stranger at
a conference without losing anything?* If the answer is no, it stays
private.

---

## 2. Repos and what they hold

### `zentory-protocol` (this repo) — PUBLIC
- Smart contracts in `contracts/src/` — public, BUSL-1.1 licensed, audited.
- Foundry test suite in `contracts/test/` — public, asserts correctness.
- Deploy scripts in `contracts/script/` — public, deterministic.
- Keeper JS skeleton in `contracts/keeper/src/` — public, but the
  *strategies it executes* are config-driven and reference off-chain
  sources only.
- Docs in `docs/` — public, including:
  - `AUDIT_HANDOFF_2026_Q3.md` — what auditors need
  - `KEY_MANAGEMENT.md` — what keys exist (without the keys)
  - `MAINNET_READINESS.md` — what blocks mainnet
  - `runbooks/keeper-live-fire.md` — operational procedure
    (does **not** contain the keys or addresses used in production)
  - `PUBLIC_VS_PRIVATE.md` — this file

### `zentory-app` — PUBLIC (AGPL-3.0)
- Next.js dApp at `app.zentorylabs.com`.
- Wallet-only onboarding (WalletConnect / wagmi / viem).
- Read-only views of contract state; write paths require wallet signature.
- AGPL-3.0 forces any hosted fork to also publish source. **This is
  intentional** — for an investor-credibility story, "AGPL-3.0 dApp
  with wallet-only onboarding" is more trustworthy than "MIT dApp you
  could secretly rebrand and run for yourself." The dApp's moat is
  its UX, its integrations, and its brand — not the JS source.

### `zentory-engine` — SOURCE-PRIVATE (proprietary license)
- Python strategy engine, signal generators, model artefacts, training
  data, hyperparameters.
- Source-available to investors and auditors under NDA + commercial
  agreement. The full source is NOT in this public repo's tree.
- **All credential material** (Supabase service-role keys, Railway
  tokens, deployer keys for engine-only operations) lives in
  Vault / Railway env / GitHub Actions secrets — never in this tree.

### `zentorylabs.com` — PUBLIC (MIT)
- Marketing site only. Static content + waitlist signup form.
- No secret material; Supabase anon key is publishable.

---

## 3. The "what goes where" decision tree

When you're about to commit something new, ask:

```
Is this on-chain, deterministic, and visible to anyone with a block explorer?
├─ YES → public repo (zentory-protocol)
└─ NO
    │
    Is this client-side JavaScript the user already has in their browser?
    ├─ YES → public repo (zentory-app or zentorylabs.com)
    └─ NO
        │
        Does this encode a competitive advantage (strategy, model, signals)?
        ├─ YES → zentory-engine (private, proprietary license)
        └─ NO
            │
            Is this an operational secret (key, token, mnemonic, RPC URL)?
            ├─ YES → .env (gitignored) + Vercel/Railway/Vault env vars only
            └─ NO
                │
                Is this an investor-facing artefact (deck, financial model)?
                ├─ YES → NDA-only distribution (Google Drive, Notion, DocSend)
                └─ NO
                    │
                    Default: ASK before committing publicly.
```

If you reach the "Default: ASK" line, ping the core team in
`#zentory-decisions` (Slack) before pushing.

---

## 4. Time-phased disclosure (the 6-month plan)

We move information through three ratchets over the next six months.
Each ratchet is gated by an external event, not by calendar.

### Ratchet 1 — "Audit-ready" (now → audit-firm engagement)
**Trigger:** A tier-1 paid audit (Nethermind / Spearbit / Trail of Bits
/ Zellic) is engaged under NDA. Estimated: 2026-09 → 2026-10.

What gets added/changed:
- This policy document moves from internal-only to public.
- `docs/AUDIT_HANDOFF_2026_Q3.md` becomes the canonical auditor
  briefing — already done.
- `docs/SECURITY_AUDIT_BRIEF.md` updated with final scope + LOC.
- `docs/AUDIT_OUTREACH.md` updated to "engaged" status.
- Whitepaper gets a "security" page with the audit firm named.
- Testnet contract addresses get pinned in repo (already done).
- Bug-bounty program listing on Immunefi goes live.
- **Nothing in zentory-engine gets opened.**

### Ratchet 2 — "Audit-complete" (audit report delivered)
**Trigger:** Paid audit report received, all Critical/High findings
fixed or formally accepted. Estimated: 2026-11 → 2026-12.

What gets added/changed:
- Audit report (executive summary) published under a stable URL.
- Full audit report (PDF) published with redactions for any
  exploit detail the auditor flags as too-sensitive-to-share.
- `docs/MAINNET_READINESS.md` updated to "mainnet-cleared" status.
- `docs/MULTISIG_MIGRATION_PLAN.md` executed; treasury multisig
  address becomes the canonical admin on every contract.
- `docs/KEY_MANAGEMENT.md` updated to reflect multisig-only admin.
- Old leaked deployer EOAs formally revoked on every contract
  via `renounceRole` or admin transfer.
- Marketing site adds "Security" page linking to the audit report.
- zentorylabs.com adds security.txt (already done).
- **Still no zentory-engine disclosure.**

### Ratchet 3 — "TGE-prep" (token generation event build-up)
**Trigger:** TGE date set. Estimated: 2027-Q1 (depends on market
conditions; not calendar-driven).

What gets added/changed:
- Treasury multisig address published on-chain and on the website.
- Token distribution contracts (vesting, airdrop) made public; they
  use the same audited contracts as the rest of the protocol.
- Tokenomics page updated with final numbers (already public).
- Bug-bounty payouts scaled up.
- **Source for zentory-engine remains private.** Possible exception:
  a "lite" open-source fork of the signal-submission interface
  (the wagmi/viem glue, no proprietary logic) may be released to
  encourage third-party quant adoption. That decision is made by
  the core team, not by individual contributors.

---

## 5. Verification protocol for unsolicited offers

This is a checklist for handling inbound messages (Telegram, Twitter
DM, Discord, email) from anyone offering "free" security services,
audits, agents, or tooling. Apply this **before** clicking any link,
running any code, or sending any message back.

### 5.1 Red flags (block immediately)
- The offer arrived unsolicited on a personal channel (Telegram, DM,
  WhatsApp) and references our project by name.
- The sender asks us to:
  - Run an `npm install` / `pip install` / `curl ... | bash` from
    their package before any signed engagement.
  - Connect our wallet to a site they control.
  - Share the repo or specific contract code with them over an
    unencrypted channel.
  - Sign anything (an NDA, an attestation, a transaction) before we
    have a written, signed engagement from a verifiable company.
- The "company" has no verifiable web presence, no LinkedIn employees,
  no prior audit reports we can find on-chain or via Code4rena /
  Sherlock / Immunefi rosters.
- The offer is "free in exchange for feedback" — see §5.2.

### 5.2 The "free" question
A real audit firm — Nethermind, Spearbit, Trail of Bits, Zellic,
ChainSecurity, OpenZeppelin, Cantina, Code4rena, Sherlock — is
verifiable through their public website, their published past audits,
and (typically) a signed MSA / SoW before any code access.

"Free" offers are usually one of:
1. **Marketing lead-gen.** The firm wants to learn our stack so they
   can pitch us a paid engagement later. Not malicious, but **not
   a substitute for a paid audit either** — they're not committing
   engineers for the duration.
2. **Code-exfiltration pipeline.** The "free agent" is a wrapper that
   uploads our codebase to the firm's servers. Even if the firm is
   legitimate, that data is now out of our control.
3. **Academic research.** Some legitimate universities (e.g., IC3,
   University of Maryland) do offer pro-bono reviews. Verify the
   professor's identity, the institution's IRB or equivalent, and
   sign a real NDA before sharing code.
4. **Insurance / underwriter due-diligence.** Some DeFi insurance
   protocols ask for source review before underwriting. The asking
   party is verifiable (Nexus Mutual, Risk Harbor, etc.). Treat
   as a normal business review with an NDA.

**Decision rule:** unless the offer falls into category 4 or a
*verified* category 3, we politely decline and continue with paid
auditors only. The cost of a paid audit (USD 30–150k) is small
relative to the cost of leaking the strategy IP.

### 5.3 Verification procedure
Before sharing code with any third party:

1. **Domain check.** Does their `@example.com` email resolve to a
   real MX? Is the domain registered to the company name (WHOIS)?
2. **LinkedIn check.** At least two employees with verifiable
   employment history at the firm.
3. **Past work.** Have they published audit reports for projects
   of similar complexity? Do those reports reference them by name?
4. **Engagement document.** A signed MSA / SoW from the company
   (not a personal Gmail) before any code is shared. The SoW must
   specify scope, duration, ownership of findings, and confidentiality.
5. **Channel.** Code goes through a private repo they control, with
   access logged and revocable; never through email attachments or
   unencrypted file shares.
6. **NDA.** Mutual NDA executed before access; survival clause of
   at least 5 years.

Until all six items are checked, the answer is no.

---

## 6. What to do if you think you leaked something

Time-to-detect matters more than time-to-contain. If you accidentally
committed a private key, a Supabase service-role key, an RPC URL, or
any of the items in §2:

1. **Stop committing.** Do not push, do not amend, do not force-push.
2. **Notify** in `#zentory-incidents` (Slack) within 5 minutes.
3. The on-call (currently the core team) will:
   - Rotate the leaked credential within 1 hour (multisig owners
     will execute the rotation; this is why the multisig exists).
   - Add a `[CVE-YYYY-NNNN]` placeholder in the incident log.
   - Open a public post-mortem at `docs/incidents/YYYY-MM-DD-<slug>.md`
     within 72 hours. We commit to public post-mortems on every
     incident that touches user funds, even if the impact was zero.

---

## 7. Why this is not "all paranoia"

The asymmetric cost is real: the upside of accidentally publishing
something is "we save a few hours of explanation to an auditor."
The downside of accidentally leaking a private key or strategy
parameter is "we lose the company." We default to private.

The places where we *do* publish (the contracts, the dApp source,
the tests, the whitepaper) are exactly the places where publication
is the *product* — it builds credibility, lets the community verify
what we built, and creates the kind of viral, trust-building presence
the project needs.

The places where we *don't* publish (the engine, the strategy
parameters, the keys) are exactly the places where secrecy is the
*product*.

If a future contributor reads this and thinks "this is overkill" —
that's the test that says the policy is working. The day it feels
paranoia is the day we don't need it.

---

*End of policy. Sign-off: core team, 2026-08-28.*
