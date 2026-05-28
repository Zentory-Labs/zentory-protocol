# ZENTORY — Go-to-Market Audit

A full, honest audit of what stands between today's testnet posture and a
credible mainnet protocol that institutional LPs, retail depositors, and
crypto-native investors will actually trust. Numbers are real (ranges from
the team's own outreach docs, market-standard quotes, and crypto-launch
benchmarks). Companion to `ROADMAP.md` (sequencing) and `TESTER_SANDBOX.md`
(testnet ops).

---

## 0. TL;DR — where you actually are

You have **built more than you've shipped**. The contracts (257/258 tests),
strategy (validated), engine (autonomous signal recorder), attribution
(Ghost Portfolio), vault that makes NAV reflect PnL (SpotVault v2, oracle-
hardened), and the testnet "shadow stack" that lets people deposit and watch
it all work are real. The whitepaper, investor FAQ (now Howey-clean), pitch
deck, partnership briefs, audit outreach plan, multisig migration plan, and
TGE structure are written.

What's missing is **execution discipline** — not engineering. Specifically:
turning the audit + legal opinion from documents into signed contracts,
seeding liquidity and insurance, switching the keeper to the SpotVault loop,
and standing in the market for 3 months with public, on-chain alpha
attribution before pulling the TGE trigger.

**Realistic budget to a credible mainnet launch: ~$500k–$1.5M.** Realistic
calendar: **6–9 months from today**. Detail below.

---

## 1. What's already done (don't rebuild)

| Area | Artifact | Status |
|---|---|---|
| Strategy | Walk-forward ensemble + hysteresis, funding-checked | ✅ committed |
| Engine | Forward recorder (live, hash-chained, hourly), Ghost Portfolio | ✅ running |
| Vault | `SpotVault` v2 (NAV ≡ PnL, Chainlink fail-closed oracle guards) | ✅ 257/258 tests |
| Testnet venue | `ShadowSpotAdapter` + `ShadowPriceOracle` + `ShadowUSDC` + one-click deploys | ✅ shipped |
| Live signal posting | Provider → router → signer dry-run; oracle pusher dry-run | ✅ armed |
| Marketing site | zentorylabs.com — WP, tokenomics, blog, FAQ, /pitch-deck, Discord/Telegram/waitlist | ✅ live (Vercel free) |
| dApp | app.zentorylabs.com — 20+ routes, signal arena, vault dep/withdraw, faucet, dashboard | ✅ live (Vercel free) |
| Keeper bot | Railway, 4H cron, settles epochs, heartbeats to Discord, Sentry | ✅ live ($5/mo) |
| Investor docs | INVESTOR_FAQ + INVESTOR_ONE_PAGER + pitch deck (HTML + MD) | ✅ written |
| Security docs | SECURITY_AUDIT_BRIEF, IMMUNEFI_SETUP, MULTISIG_MIGRATION_PLAN | ✅ written |
| Partnership | HYPERLIQUID_PARTNERSHIP_BRIEF + ONE_PAGER | ✅ drafted |
| Legal prep | LEGAL_COUNSEL_SHORTLIST, GEOBLOCKING (N-02), BUYBACK_DESIGN (Howey-clean) | ✅ written |

This is **not pre-seed scaffolding.** It is seed-stage groundwork. Treat it
as such — most of the next-step work below is *executing* documents that
already exist, not writing new ones.

---

## 2. The genuine gaps, by layer

### 2.1 Smart Contracts — *audit-gated*
- ❌ **SpotVault v2 not deployed.** Built + tested; needs the shadow stack
  on testnet, then external audit before mainnet.
- ❌ **Production SpotExecutionAdapter** (Hyperliquid spot via CoreWriter)
  — not built; needs HyperCore docs + audit. Shadow adapter is testnet-only.
- ❌ **External audit not yet booked.** Per `AUDIT_OUTREACH.md` the
  shortlist is Spearbit/Cantina ($80–150k, 4–8 wk), Trail of Bits ($150–
  300k, 8–12 wk wait), Code4rena/Sherlock contest ($50–100k pool, 1–2 wk).
  **Do this in the next 2 weeks** — wait-lists are real.
- ❌ **Immunefi bounty live.** Per `IMMUNEFI_SETUP.md` the plan exists;
  $25k–50k starting pool is enough to be credible post-audit. Launch the
  bounty *after* the firm audit lands, *before* mainnet.

### 2.2 Engine + Signal Generation
- ⚠️ **Keeper not yet pointed at SpotVault loop.** The keeper currently
  only calls `EpochScoring.settleEpoch`. It needs two more responsibilities:
  `oracle.setPrice(...)` and `vault.rebalanceTo(...)`. Scripts exist
  (`oracle_pusher.py`); wiring into Railway = ~1 day of operator work.
- ⚠️ **No live signal yet posted on-chain.** SignalRegistry has 0 entries.
  The full signing chain is dry-run-proven; flipping to live requires the
  keeper's `authorizedSigner` key + the new SignalRegistry address — the
  existing one is from the 2026-05-27 redeploy and is correctly wired.

### 2.3 Backend Infra — *blocking serious users*
- ❌ **Free-tier Supabase** (deleted once already per session history).
  Move to **Supabase Pro ($25/mo)** before any LP deposit — single point
  of failure for the indexer.
- ❌ **Free-tier Vercel** for both dApp + marketing. **Pro tier ($20/mo
  per site)** for branch deploys, analytics, and reliable auto-deploys.
  The 2026-05-27 stale-deploy issue (`/press`, `/blocked` 404s) won't recur.
- ❌ **Single RPC.** Per `RPC_PROVIDER_COMPARISON.md` the team chose
  Alchemy already; need to confirm a **second RPC fallback** in keeper +
  indexer (Quicknode or HypeRPC) so a single Alchemy outage doesn't stop
  the protocol. Alchemy Growth $49–299/mo + 2nd at similar.
- ❌ **Secrets on OneDrive auto-sync** (audit F-02). Move to **1Password
  Business ($8/user/mo)** or AWS Secrets Manager. ~1 day of work.
- ❌ **Monitoring is hobby-grade.** UptimeRobot free + Sentry free + Discord
  webhook is fine for a testnet toy; for mainnet add **Tenderly Pro for
  contract monitoring ($120/mo)** and an on-call rotation.

### 2.4 dApp / Frontend
- ❌ **Ghost Portfolio tile not on the vault page.** The engine computes
  HOLD/GHOST/ACTUAL; the dApp needs the UI component. This is **THE
  homepage screenshot** for investors. 2–5 days of frontend work.
- ❌ **Live signal widget** (LONG/FLAT, time-since-last-rebalance, signed
  signal history) not built. Same 2–5 days.
- ⚠️ **Demo mode vs live mode honesty** — the dApp supports demo mode; needs
  clear visual labeling so testers know what's real.
- ⚠️ **/admin route guard** + hydration errors (session history #82–87) —
  cleanup before public eyes.

### 2.5 Marketing Site
- ⚠️ **Stale Vercel deploys** — `/press` and `/blocked` were 404 mid-session.
  Move to Vercel Pro **OR** wire the GH Action with `VERCEL_TOKEN` so the
  push-fallback workflow works.
- ❌ **The N-02 geo-block not live** until the redeploy. Until then, the
  marketing site is *not* protecting itself from blocked jurisdictions.
  Critical pre-TGE.
- ✅ Whitepaper, tokenomics, blog, /pitch-deck all live and largely clean
  (FAQ buyback-burn just fixed this session).
- ❌ **Demo video / explainer video** — not present. A 90-second
  vault-deposit-watch-NAV-rise demo is the single piece of content that
  converts. Budget: $3–10k for a quality animator + voiceover, or
  $500–2k for a screen-recorded Loom-style version.
- ❌ **Twitter/X presence** — STATE.md mentions Discord + Telegram + waitlist,
  but no organic Twitter funnel. KOL outreach below.

### 2.6 Security & Ops
- ❌ **Multisig migration not executed.** Per `MULTISIG_MIGRATION_PLAN.md`
  the plan is a 3-of-5 Safe; needs 5 hardware wallets (~$200 ea = ~$1k),
  the testnet dry-run, then mainnet at deploy time. **Hard blocker for
  mainnet** — currently a single EOA (and a known-leaked deployer) holds
  admin on critical contracts.
- ❌ **Deployer key rotation.** The leaked 2026 deployer key should be
  retired post-multisig migration — every contract still admin'd by it is
  a liability.
- ❌ **Immunefi bounty not yet listed.**

### 2.7 Legal / Regulatory
- ❌ **Legal opinion not commissioned.** Per `LEGAL_COUNSEL_SHORTLIST.md`
  the candidates are scoped; need to **engage** one. Realistic cost
  $40–80k for token classification + ToS + entity structure + risk
  disclosures. This is **gating to TGE.**
- ❌ **Foundation / entity not set up.** BVI / Cayman / Marshall Islands
  foundation setup $10–30k + $5–15k/yr. Pick after counsel advises.
- ❌ **Geo-block enforcement** — designed in `GEOBLOCKING.md` but not live
  (see §2.5).
- ✅ Howey contradiction in FAQ now fixed (this session).
- ⚠️ Whitepaper §6.3 says supply allocation TBD — match it to `TGE_STRUCTURE.md`
  before any investor reads both.

### 2.8 Tokenomics & TGE
Per `TGE_STRUCTURE.md`: Team 18% / Treasury 20% / Quant rewards 22% / LP
rewards 10% / POL 8% / Airdrop 3% = **81% accounted for**. Implication:
**~19% earmarked for seed/strategic/public sale** — needs to be
explicit in the public tokenomics, *and the legal opinion must approve
the structure of any private raise* (SAFT vs token warrant vs equity-with-
token-rights). Today this is the most under-specified piece.

- ❌ **Seed/strategic round terms not defined.** Cap, valuation, token
  lock, jurisdiction restrictions. Drives directly into the "investor
  confidence" checklist below.
- ❌ **TGE float < 5–8%** target per `TGE_STRUCTURE` — confirm pricing
  protection + MM arrangement before listing.

### 2.9 Liquidity & MM
- ❌ **No MM partnership signed.** For a credible HyperSwap listing + any
  CEX path, you want **Wintermute / GSR / FlowDesk / Auros** options.
  Typical: $50–200k cash + a token loan structure. Reach out *6–8 weeks
  pre-TGE.*
- ❌ **POL USDC side not funded.** TGE_STRUCTURE earmarks 80M ZENT for
  POL but not the USDC counterpart. Need **$100–500k USDC** parked on the
  initial pool to make ZENT/USDC tradeable without immediate slippage death.

### 2.10 Insurance & Treasury
- ❌ **Insurance fund unseeded.** `FeeDistributor` routes 15% of fees to
  it, but at launch with no fees yet, the pool is empty. For a credible
  "non-custodial vault" pitch, seed **$500k–$2M** stables before public
  TVL targets.
- ❌ **Treasury management plan absent.** Treasury is 20% of supply
  (200M ZENT). Who custodies, who signs, what diversification policy
  (e.g. convert X% to stables for runway, hold Y% in BTC, etc.).

### 2.11 Track Record (the existential gap)
- ❌ **Zero on-chain track record.** No real signals posted, no real
  vault TVL beyond seed. **This is the gap nothing else fixes.** Phase 1
  of `ROADMAP.md` is to mint this — *forward*, *publicly*, *for at
  least 3 months*. Without it, investor diligence stalls.

---

## 3. Steps to launch, in order (timeline)

### Weeks 0–2 (operator work, parallel)
1. Engage **2 audit firms** (Spearbit + Cantina, or Spearbit + ToB),
   collect quotes. ($0 to engage; commit one within 2 weeks.)
2. Engage **1 crypto-native legal firm** for the scoping call.
3. **Multisig migration on testnet** (`MULTISIG_MIGRATION_PLAN`).
   $1k hardware wallets + 1 day of work.
4. Set up **paid Vercel + Supabase Pro + 1Password + 2nd RPC fallback**.
   ~$500/mo, 1 day.
5. Deploy the **shadow stack + SpotVault** (one click each). Grant roles,
   fund reserves, wire keeper to push prices + drive rebalances.
6. Push the **Ghost Portfolio + Live Signal tile to the dApp.** Frontend
   work, 1–2 weeks.

### Weeks 2–14 (Phase 1 — public testnet run)
7. **Onboard 5–10 testers via `TESTER_SANDBOX.md`.** Publish weekly
   updates with on-chain signal-alpha numbers.
8. **External audit runs in parallel** (4–8 weeks once kicked off).
9. **Legal opinion delivered** (4–8 weeks).
10. **Foundation/entity registered.**
11. **Demo video** ($2–10k).
12. **KOL warm-ups** (see §5).

### Weeks 14–22 (audit remediation + bounty + MM)
13. Audit remediation; **Code4rena / Sherlock** sweep on the remediated code.
14. **Launch Immunefi bounty** ($25–50k pool).
15. **Sign an MM** (8 weeks pre-TGE minimum).
16. **Seed insurance** ($500k+ stables).
17. Final dApp + marketing polish; Twitter/X content cadence ramps.

### Weeks 22–30 (TGE)
18. **Mainnet deploy** of the audited stack (with multisig admin from
    deploy time, not migrated post).
19. **TGE** with ≤5–8% float, MM live, POL seeded.
20. **Phase 2 marketplace** open *to the first cohort of external quants*
    once TVL clears a stated threshold (e.g. $1M).

---

## 4. COSTS — real figures

### One-time, pre-mainnet
| Item | Range | Note |
|---|---|---|
| External audit (1 firm: Spearbit/Cantina) | **$80k–150k** | per `AUDIT_OUTREACH` |
| Code4rena / Sherlock sweep (optional) | $50k–100k | after firm audit |
| Trail of Bits (premium tier, optional) | $150k–300k | only if a CEX listing needs the badge |
| Legal opinion + ToS + entity setup | **$40k–80k** + $10k–30k entity | per `LEGAL_COUNSEL_SHORTLIST` |
| Immunefi bounty pool | **$25k–50k** | starting; can grow |
| MM deal (cash side, ex-token loan) | **$50k–200k** | Wintermute/GSR/FlowDesk |
| POL USDC side | **$100k–500k** | depends on TVL ambitions at listing |
| Insurance fund seed | **$500k–2M** | gating LP confidence |
| Multisig hardware wallets (5×) | $1k | |
| Demo video + marketing creative | $5k–30k | |
| Brand polish / design refresh | $5k–20k | |
| Initial KOL / PR push | **$30k–100k** | typical seed-stage push |
| **Subtotal one-time** | **~$300k (scrappy) / ~$700k (sensible) / ~$2.5M (premium)** | |

### Recurring (annual)
| Item | Range |
|---|---|
| Infra (paid Vercel ×2 + Supabase Pro + Alchemy Growth + Quicknode + Tenderly + 1Password + UptimeRobot + monitoring) | **$3k–12k/yr** |
| Foundation / accounting / compliance retainer | **$15k–60k/yr** |
| Legal retainer (post-launch) | **$20k–80k/yr** |
| Community manager + content (1 person 50%) | **$30k–80k/yr** |
| MM relationship (after initial deal) | $0–100k/yr |
| Sentry / Datadog / observability upgrades | $5k–20k/yr |
| **Subtotal annual** | **~$80k–350k/yr** |

### Bottom-line ranges to mainnet
- **BARE-MINIMUM scrappy launch** (light audit, founder-led legal, no MM,
  minimal marketing, $500k insurance): **~$300–500k.**
- **CREDIBLE seed-quality launch** (good audit + sweep, real counsel,
  signed MM, $1M insurance, real marketing): **~$700k–1.5M.**
- **PREMIUM institutional launch** (ToB + sweep, tier-1 counsel, Wintermute,
  $2M insurance, full press): **$1.5M–3M+.**

If you're not raising capital before TGE, the **bare-minimum path is
possible**, but it caps you out of institutional LP money (they want the
premium signals). If you raise a seed of $1–3M at strategic-round pricing,
the credible path is feasible without rugging founder/treasury.

---

## 5. What investors actually want (the confidence checklist)

In rough order of what gets them to "yes":

1. **A live thing they can use.** The dApp + shadow vault is the killer
   demo — let them deposit testnet WBTC and watch NAV move with on-chain
   signal alpha *in real time*. This converts.
2. **A track record.** Phase 1 = at least 3 months of public, on-chain
   `GHOST > HOLD` data. Anything less and you're selling a story.
3. **Named team with real backgrounds.** A LinkedIn-verifiable founder
   with relevant quant/protocol history. Pseudonymity is a discount.
4. **Audit + bounty + legal opinion.** Documents, not promises.
5. **Multisig + secrets hygiene.** Single EOA admin = automatic no.
6. **Clean Howey/securities posture.** The FAQ is now clean — keep it
   that way in every channel.
7. **Token model that doesn't smell like a rug** — low float, vesting,
   no team unlock for ≥1 year past TGE, MM-supported listing.
8. **Defensibility story.** "Every signal signed on-chain forever" is
   genuinely defensible; lead with it.
9. **Hyperliquid partnership.** The brief exists. A formal nod from
   Hyperliquid team is worth tens of bps of trust.
10. **Insurance fund seeded.** Concrete proof of skin in the game.

---

## 6. How to get people hyped (without breaking the legal posture)

This is fundable as a story, but only if you stop selling the token and
start selling the **vault** and the **moat.**

- **Lead with the live demo, not the token.** "Deposit BTC, watch the
  vault beat HOLD-in-BTC, see every signal forever on-chain." Token =
  utility footnote, never headline.
- **Twitter/X cadence.** Daily threads from the vault's autonomous
  recorder showing GHOST−HOLD. Weekly deeper essays (you already have a
  great blog catalog — repurpose). Aim for 5k followers before TGE.
- **Podcast circuit** (KOL warm-ups, ~10 weeks pre-TGE):
  Bankless, Empire (Yano + Santiago), Lightspeed, The Edge of Show,
  HyperLiquid Cast, Mint. Pitch: "first protocol with on-chain alpha
  attribution." The data, not the airdrop.
- **Hyperliquid co-marketing.** Use `HYPERLIQUID_PARTNERSHIP_BRIEF`.
  If they amplify, that's worth more than $50k of paid KOL.
- **Investor whitepaper PDF + 5-slide tear-out** from the existing pitch
  deck for warm intros. Most VCs will not read your full deck on cold
  outreach.
- **Pre-launch waitlist hardcap** — gives scarcity. 10,000 testnet users
  → top 1,000 get whitelist on real launch.
- **Avoid hype that becomes a lawsuit** — never say "ZENT will go up",
  "buy ZENT to earn", "guaranteed yield". The whitepaper has the right
  language; reuse it in every marketing channel.

---

## 7. Top 5 risks I'd flag to anyone investing

1. **No proven alpha yet.** Honest. Mitigation = Phase 1 public run.
2. **Single-chain dependency on Hyperliquid.** ~12-month-old chain;
   validator centralization in their own risk disclosure. Mitigation =
   document why you bet on HyperEVM and what's your contingency.
3. **Two-sided cold-start.** Need quants AND capital simultaneously.
   Mitigation = run the house strategy as the canonical first quant; open
   marketplace only after the house vault has TVL.
4. **Regulatory drift.** Token classification can shift; SEC/CFTC March 2026
   guidance is helpful but not binding. Mitigation = clean utility framing
   + counsel-approved disclaimers + US-block at frontend.
5. **Operational hygiene** — leaked deployer key, OneDrive secrets, free-
   tier infra. Mitigation = §3 weeks 0–2 above.

---

## 8. The honest bottom line

**You have ~80% of what's needed to launch already built or written.** The
remaining 20% is paid services + calendar time, not engineering. The
question is no longer "what should we build?" — it is **"in what order do
we spend $500k–$1.5M and 6–9 months to land this credibly?"**

The single highest-impact use of the next two weeks of your time:
1. Sign a contract with **one audit firm** (Spearbit or Cantina).
2. Sign a contract with **one legal firm** for the scoping call.
3. Execute the **multisig migration** on testnet.
4. Deploy the **shadow vault** and **start the 3-month clock**.

Everything else can be done while those four are running.

— end —
