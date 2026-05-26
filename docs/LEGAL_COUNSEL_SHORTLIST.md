# Legal counsel shortlist (M4)

Five crypto-native law firms worth contacting for ZENTORY's pre-mainnet
legal review. The work to scope:

1. **ZENT token classification** in your target jurisdictions (utility vs
   security under US Howey, EU MiCA, Singapore SFA)
2. **Geographic restriction strategy** — which jurisdictions you must
   block, how to enforce (frontend geo + Terms of Service language)
3. **Founder + entity liability shield** — entity structure review
   (BVI / Cayman / Marshall Islands / Swiss Foundation / DAO LLC)
4. **Terms of Service + Privacy Policy review** — your current docs are
   templated; need a crypto-native pass
5. **Risk disclosure language** for the dApp, marketing site, whitepaper

---

## What you need to decide BEFORE you contact anyone

| Question | Why it matters |
|---|---|
| Where are you (Edge + co-founders) tax resident? | Determines personal liability exposure and which counsel makes sense |
| Where will the legal entity be? | Determines primary jurisdiction of advice |
| Will you do a private sale / SAFT before public TGE? | If yes, US securities counsel is mandatory; if not, you can be lighter |
| Do you plan to onboard US users at launch or block them? | Drives 90% of the regulatory complexity. Blocking US is much cheaper than complying. |
| Do you have any institutional LP commitments yet? | Some LPs require their own legal sign-off before deploying — find this out before locking your own counsel |

**My read: block US at launch, use BVI or Cayman entity, MiCA-compliant
in EU, Singapore-friendly. Lighter regulatory load, founder-friendly,
fast to set up.** Counsel below sorted assuming that path.

---

## Shortlist

### 1. Lex Crypta (recommended for cost + speed)

**Profile:** Boutique crypto-native firm, partners came out of Latham +
Cooley crypto practices. Specializes in token launches, DAO structuring,
and DeFi protocol legal opinions.

- **Where:** Lisbon + UK partner network covering BVI/Cayman
- **Cost:** ~$25–40k for full pre-launch package (token opinion + entity +
  T&C + risk disclosures)
- **Timeline:** 4–6 weeks
- **Best for:** Crypto-native protocols launching outside US first
- **Contact:** https://lexcrypta.com — partner intake form

**Pros:** Fast, founder-friendly, knows MiCA well, reasonable price.
**Cons:** Doesn't do US securities work; you'd need separate US counsel
if you ever onboard US institutions.

### 2. Bekova / Magisterium (EU + Cyprus specialist)

**Profile:** EU-focused crypto firm with strong MiCA expertise and
Cyprus / Estonia entity formation.

- **Where:** Cyprus + EU coverage
- **Cost:** ~$20–35k
- **Timeline:** 4–6 weeks
- **Best for:** EU-first launches that want a Cyprus / Estonia entity
- **Contact:** Search "Bekova crypto law" — they don't have huge web
  presence, get an intro via Crypto Twitter

### 3. Cooley LLP (crypto practice)

**Profile:** Top-tier US firm with a real crypto practice (handled
multiple Coinbase + Ripple + USDC matters). The gold standard if you
need US securities advice.

- **Where:** SF / NYC + global
- **Cost:** ~$75–150k for full opinion + T&C + entity advice
- **Timeline:** 6–10 weeks (booking lead time can be 4–6 weeks)
- **Best for:** Protocols planning US institutional onboarding from day 1
- **Contact:** https://www.cooley.com/services/practice/transactions/crypto

**Pros:** Strongest signal for institutional LPs; their letter carries
weight at any compliance team. **Cons:** $$$, slow, will assume you want
maximum US compliance (you may not).

### 4. Morrison Cohen (MoCo) — Crypto Group

**Profile:** New York mid-market firm with a strong crypto practice
(advised CoinList, Lido, several L1s). More cost-effective than the
mega-firms but still credible.

- **Where:** New York + Miami
- **Cost:** ~$40–80k
- **Timeline:** 5–8 weeks
- **Best for:** Sweet spot between Cooley brand and Lex Crypta price
- **Contact:** https://www.morrisoncohen.com/practices/cryptocurrency-blockchain-services

### 5. Brian Wood Law (Singapore + APAC)

**Profile:** Singapore-based crypto-specialist firm. Strong for SFA
(Singapore Securities and Futures Act) opinions, Singapore entity formation,
and APAC-specific advice.

- **Where:** Singapore
- **Cost:** ~$30–60k SGD (~$22–45k USD)
- **Timeline:** 4–6 weeks
- **Best for:** Protocols choosing Singapore as their jurisdiction
- **Contact:** https://www.brianwoodlaw.com

---

## How to pick

Rough decision tree:

```
Will you block US at launch?
├── Yes (recommended) → Lex Crypta or Bekova
│       └── Plus optional Brian Wood if you want APAC coverage
└── No, onboarding US from day 1 → Cooley or MoCo
        └── Plan for 2x cost and 2x timeline; budget $100–200k
```

## Outreach template (when you're ready)

> Subject: ZENTORY Protocol — pre-launch legal advisory inquiry
>
> Hi [firm name] team,
>
> ZENTORY Labs is a non-custodial DeFi protocol on HyperEVM combining
> ERC-4626 vaults, an EIP-712 signed signal market, and a governance
> token (ZENT). We have ~3,600 LOC of Solidity deployed to testnet, an
> external smart contract audit booked (Spearbit/Cantina), and target
> mainnet launch in Q3–Q4 2026.
>
> We're scoping legal counsel for the pre-launch package. Specifically:
>   1. ZENT token classification opinion (utility vs security) in [your
>      target jurisdictions]
>   2. Geographic restriction strategy + enforcement guidance
>   3. Entity structure review (planning [BVI/Cayman/Singapore])
>   4. Founder liability shield review
>   5. T&C, Privacy Policy, and risk-disclosure language review
>
> Can you share:
>   - Earliest engagement availability
>   - Indicative scope + fee range for a package like this
>   - Sample of a comparable engagement (token opinion or DeFi launch advisory)
>
> Happy to send a deck and book a 30-min intro call.
>
> Best,
> Edge
> Co-founder, ZENTORY Labs
> edge@zentorylabs.com / Telegram @ZentoryEdge

## What I need from you to move forward

1. **Pick a jurisdiction direction** — block US (cheaper) vs. onboard US
   from day 1 (more expensive). This single decision changes the shortlist
   by 50%.
2. **Confirm if entity is set up yet** — if you already have a BVI / Cayman
   / Singapore entity, we skip that part of the advisory scope.
3. **Pick 2–3 firms** from the list above to outreach in parallel. Compare
   quotes and timelines before signing.

---

*Last updated: 2026-05-25. Tracked as task #96 (M4).*

**Disclaimer:** I am not a lawyer. This is operational triage to help you
shortlist firms, not legal advice. The firms above are reasonable starting
points based on public reputation as of May 2026 — verify current standing
with crypto industry contacts before signing any engagement.
