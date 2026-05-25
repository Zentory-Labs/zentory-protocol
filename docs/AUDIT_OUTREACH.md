# Audit firm outreach

How to actually approach Spearbit, Cantina, and (optionally) Trail of Bits / Code4rena to scope ZENTORY's pre-mainnet audit.

Goal: get 2–3 firm proposals back within 2 weeks so we can pick on **scope clarity, team quality, calendar fit, and price** — not just on price.

---

## 1. Shortlist & how to reach them

### Spearbit  *(top pick)*
- Cantina is Spearbit's spinout / front-of-house. Same auditors, different intake.
- **Best fit because:** they specialize in DeFi infra of exactly this size (1k–5k LOC), they have a strong bench of solo researchers who can take medium-scope engagements without 3-month lead time, and their reports are public-quality.
- **How to apply:** https://cantina.xyz/welcome (Cantina is the easier door) — submit via the "Get an audit" form. Or DM `@spearbit` on Twitter / `@spearbit-team` on Telegram.
- **Typical timeline:** 4–8 weeks from kickoff. Engagement booking 4–8 weeks out.
- **Typical price for our scope:** USD $80k–150k.

### Cantina  *(same firm, different intake)*
- **How to apply:** https://cantina.xyz/welcome — same form, same auditors.
- Treat as a parallel application to Spearbit. You may get back two quotes; pick the team you click with.

### Trail of Bits
- **Best fit because:** strongest brand signal for institutional LPs / token listings post-launch. Their report is "gold standard" for investor diligence.
- **Downside:** $150–300k+ for our scope, 8–12 week wait list. Usually overkill at testnet → mainnet stage; great for v2 / large TVL milestones.
- **How to apply:** https://www.trailofbits.com/contact-engagement/ or contact@trailofbits.com
- **Recommendation:** apply but expect a longer / more expensive proposal. Keep as the "premium tier" comparison.

### Code4rena / Sherlock *(contest, supplement)*
- **Best fit because:** broad-coverage sweep at lower cost, runs in parallel with the firm audit. Pays per-finding to a competitive pool of wardens.
- **Cost:** $50k–100k (the bounty pool). Less predictable than a firm audit.
- **Timeline:** 1–2 weeks active contest + 2 weeks judging.
- **How to apply:** Code4rena: https://code4rena.com/sponsor / Sherlock: https://www.sherlock.xyz/start-a-contest
- **Recommendation:** **after** the firm audit lands, run a Sherlock 1-week sweep to backstop the remediation. Lots of eyes, no real prep cost from us.

---

## 2. The first email — keep it short

The brief at `docs/SECURITY_AUDIT_BRIEF.md` is the long version. **Do not send that first.** Send this short version, attach the brief or link to the repo, and let the firm pull more if interested:

> **Subject:** ZENTORY Protocol audit inquiry — multi-asset quant vaults on HyperEVM (~3.6k LOC)
>
> Hi Spearbit team,
>
> ZENTORY Labs is a non-custodial Alpha Vault + signal-arena protocol on HyperEVM. We have ~3,586 LOC of Solidity across 26 files (ERC-4626 vaults, EIP-712 signal registry, epoch-scoring keeper, governance Timelock) deployed on testnet and ready for a formal audit ahead of mainnet launch in Q3–Q4 2026.
>
> I'm reaching out to scope an engagement. We have:
> - Public repo: https://github.com/Zentory-Labs/zentory-protocol
> - Full audit brief with scope, threat model, and prior internal work: https://github.com/Zentory-Labs/zentory-protocol/blob/main/docs/SECURITY_AUDIT_BRIEF.md
> - Slither + internal pentest reports already in-repo
> - Budget range we're working with: $80–200k for Phase 1+2
>
> Can you share:
> 1. Earliest engagement slot
> 2. Indicative team size + sample report for a comparable engagement
> 3. Quote (or quote range) for Phase 1+2 as described
>
> Happy to jump on a 30-min walkthrough call if useful.
>
> Best,
> Edge
> Co-founder, ZENTORY Labs
> edge@zentorylabs.com / Telegram @ZentoryEdge

**Personalize per firm:** swap "Spearbit team" for "Cantina team", "Trail of Bits team", etc. Mention any prior interaction / referral / specific researcher you'd like on the team if you have one.

---

## 3. What firms will ask back

Be ready with:

| Question | Answer ready in |
|---|---|
| Codebase size + frozen commit | `git rev-parse main` + LOC from `find contracts/src -name '*.sol' -exec wc -l {} +` |
| Existing tests / coverage | 17 forge test files, no formal coverage % yet |
| Static analysis history | `docs/reports/slither-2026-04-26.json` |
| Pentest history | `docs/reports/pentest-2026-04-26.md` |
| External dependencies | OpenZeppelin Contracts 5.x (audited upstream), Hyperliquid L1 precompiles (out of scope) |
| Threat model | §4 of `SECURITY_AUDIT_BRIEF.md` |
| Remediation expectation | We commit to ≤5 business days turnaround per HIGH+ finding |
| Public disclosure | Final report is public; pre-launch findings stay private until remediation lands |

---

## 4. Comparing proposals — what to look for

When the proposals come back:

- ✅ **Named auditors** (not "TBD" — you want to know who's reading your code)
- ✅ **Concrete schedule** (specific weeks, not "Q3 sometime")
- ✅ **Sample report** from a similar engagement (DeFi infra, ~1–5k LOC)
- ✅ **Clear out-of-scope statement** (what they explicitly won't review)
- ✅ **Remediation re-review clearly priced** (don't sign without knowing this)
- ⚠️ **Price too cheap (<$60k)** — likely junior team or scope-cut; ask why
- ⚠️ **Price too high (>$300k)** — overkill unless they're including extras like formal verification

---

## 5. Decision criteria — weighted

When picking the firm:

| Factor | Weight | Why |
|---|---|---|
| Quality of sample report | 40% | This is what investors see |
| Team experience with ERC-4626 + signal markets | 25% | Closer to our domain = fewer wasted hours |
| Calendar fit | 20% | We need them before Q4, not Q1 next year |
| Price | 15% | All three target firms are in budget — price tiebreaker only |

Note: **price is last.** A $120k audit that finds the right things is infinitely cheaper than a $50k audit that misses a critical bug.

---

## 6. After signing

We'll:

1. Freeze a release branch on the audit commit (`audit/2026-Qx-spearbit`)
2. Grant the firm read access to that branch + read on `contracts/broadcast/`
3. Schedule the kickoff call (1–2 hours, full team)
4. Set up a private Telegram or Slack channel for ongoing questions
5. Block our calendars for the remediation week so we're not bottlenecked

---

*Last updated: 2026-05-25*
