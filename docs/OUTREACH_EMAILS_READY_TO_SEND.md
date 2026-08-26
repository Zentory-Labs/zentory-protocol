# Outreach emails — ready to send

Personalized drafts for the next 5 outreach steps. Each one is ready to
copy-paste with one or two field substitutions ([fill in] markers).

Send order:

| Priority | Recipient | Purpose | Lead time |
|---|---|---|---|
| 1 | Cantina | Smart contract audit (primary pick) | 4–6 wk booking |
| 2 | Trail of Bits | Smart contract audit (premium comparison) | 8–12 wk booking |
| 3 | Lex Crypta | Legal counsel (primary pick — block US, BVI/Cayman entity) | 4–6 wk engagement |
| 4 | Cooley LLP | Legal counsel (alternative — if US onboarding from day 1) | 6–10 wk engagement |
| 5 | QuickNode Support | Provision HyperEVM custom RPC endpoint | 1–2 wk lead time |

Send 1 + 3 + 5 today if you want the most leverage. The others are
comparison quotes or fallbacks.

**Audit anchor for all firm conversations:** frozen branch **`audit/2026-Q3b`**
(re-frozen 2026-08-21 at commit `1f83fcbc` = `main` @ `3585752` + the readiness
re-stamp; verified green at that commit during M5-F5 handoff) — hand firms the
branch, not `main`. Readiness package:
[docs/AUDIT_READINESS.md](https://github.com/Zentory-Labs/zentory-protocol/blob/audit/2026-Q3b/docs/AUDIT_READINESS.md).
Tier 0 remediation queue:
[docs/security/TIER_0_FIX_QUEUE.md](https://github.com/Zentory-Labs/zentory-protocol/blob/main/docs/security/TIER_0_FIX_QUEUE.md).

---

## 1. Cantina — Smart contract audit

**Submit at:** https://cantina.xyz/welcome (Get an audit form)
**Backup email:** support@cantina.xyz

> **Subject:** ZENTORY Protocol audit inquiry — non-custodial drawdown-defense vaults on HyperEVM (~3.6k LOC)
>
> Hi Cantina team,
>
> ZENTORY Labs builds non-custodial ERC-4626 vaults on HyperEVM that hold the
> underlying asset in uptrends and rotate to cash in downturns (spot only, no
> leverage), plus an on-chain research/signal layer with slashable ZENT-staked
> reputation. 29 Solidity contracts (~3.6k LOC) are deployed on testnet
> (chain 998) and frozen for audit; the external audit is the first of three
> hard mainnet gates (audit, 3-of-5 multisig migration, 3-month public track
> record), so your engagement is literally our critical path.
>
> **Quick architecture summary:**
> - ERC-4626 vaults: zBTC, zETH, zSOL, zXRP + SpotVault (oracle-valued, long/flat via signed `rebalanceTo`)
> - EIP-712 signed signal registry; 4-hour epoch scoring settles accuracy on-chain
> - StrategyExecutor: two signed paths (perp TradeSignal + spot target-weight Rebalance), mandate-bounded
> - MedianOracle (multi-signer median NAV feed) + HyperSwapRouterAdapter (atomic spot venue)
> - OpenZeppelin Timelock + Governor (uniform 66% supermajority) governance stack
>
> **What we have in-repo (public):**
> - Frozen audit branch: `audit/2026-Q3b` — https://github.com/Zentory-Labs/zentory-protocol/tree/audit/2026-Q3b
> - Readiness package (inventory, threat model, prior findings + dispositions): [docs/AUDIT_READINESS.md](https://github.com/Zentory-Labs/zentory-protocol/blob/audit/2026-Q3b/docs/AUDIT_READINESS.md)
> - Audit brief: [docs/SECURITY_AUDIT_BRIEF.md](https://github.com/Zentory-Labs/zentory-protocol/blob/audit/2026-Q3b/docs/SECURITY_AUDIT_BRIEF.md)
> - Internal Slither + manual pentest reports committed, all findings triaged with dispositions
> - **384 Foundry tests across 38 files — including invariant suites (vault + executor), fuzz suites, a cross-language EIP-712 digest-parity test against our Python signer, and an end-to-end signed spot-rebalance integration test.** Live tail at the frozen commit (`1f83fcbc`): 383 passed / 0 failed / 1 intentional skip.
> - Design-decision records for the two most recent changes (scoring formula, governance supermajority) in `docs/decisions/`
>
> The vault loop already runs autonomously on testnet (keeper-signed 4-hourly
> rebalances, NAV indexed and published against a hash-chained public ledger) —
> you'd be auditing a running system, not a paper design.
>
> **Budget range:** USD $80–200k for Phase 1+2. Standard 50% engagement / 50% draft delivery split.
>
> **Timing:** Audit window July–September 2026. Earliest start preferred. Willing to be flexible to fit your bench schedule.
>
> Three things I'd love to get back from you:
> 1. Earliest engagement slot
> 2. Indicative team size + 1–2 sample reports for a comparable engagement (DeFi infra, similar LOC)
> 3. Quote (or quote range) for Phase 1+2 as described
>
> Happy to jump on a 30-min walkthrough call once you've had a chance to skim the readiness package.
>
> Best,
> Edge
> Co-founder, ZENTORY Labs
> info@zentorylabs.com
> Telegram: @ZentoryEdge

---

## 2. Trail of Bits — Smart contract audit (premium comparison)

**Submit at:** https://www.trailofbits.com/contact-engagement/
**Backup email:** contact@trailofbits.com

> **Subject:** Engagement inquiry — ZENTORY Protocol audit, non-custodial vaults on HyperEVM
>
> Hi Trail of Bits team,
>
> Reaching out to scope a smart contract audit for ZENTORY Labs. The external
> audit is the first of three hard gates before our HyperEVM mainnet launch
> (audit, multisig migration, 3-month public track record — realistically ~Q1 2027).
>
> **Codebase:** 29 Solidity contracts, ~3.6k LOC, frozen for audit on branch
> `audit/2026-Q3b`. ERC-4626 drawdown-defense vaults (incl. an oracle-valued
> SpotVault driven by EIP-712-signed target-weight rebalances), a signal
> registry with on-chain epoch scoring, a multi-signer median NAV oracle, and
> an OpenZeppelin governance stack with a uniform 66% supermajority.
> Public repo: https://github.com/Zentory-Labs/zentory-protocol
>
> **What's already done:** Internal pentest + Slither (180 findings, triaged with
> written dispositions; highs fixed and re-verified), two internal audit rounds, a
> 2026 exploit-landscape re-scan, and **384 Foundry tests across 38 files (incl.
> invariant + fuzz suites and a cross-language EIP-712 digest-parity test)** —
> live tail at the frozen commit (`1f83fcbc`) is 383 passed / 0 failed / 1 skip.
> Full readiness package: [docs/AUDIT_READINESS.md](https://github.com/Zentory-Labs/zentory-protocol/blob/audit/2026-Q3b/docs/AUDIT_READINESS.md)
>
> Budget envelope is open up to ~$300k for the right firm + team — we're sourcing comparison quotes from Cantina and one contest provider as well. ToB's report carries the strongest institutional signal for our target LPs, so we'd weight your proposal accordingly.
>
> Can you share:
> 1. Earliest engagement availability (we can wait into Q4 if the right team is the bottleneck)
> 2. Proposed team composition + 1–2 sample reports for a comparable DeFi engagement
> 3. Fee range for Phase 1+2 covering the scope in the brief
> 4. Whether you'd be open to a 1–2 week follow-on remediation review at hourly rate
>
> Happy to schedule a deeper architectural walkthrough whenever your team is ready.
>
> Best,
> Edge
> Co-founder, ZENTORY Labs
> info@zentorylabs.com
> Telegram: @ZentoryEdge

---

## 3. Lex Crypta — Legal counsel (primary)

**Submit at:** https://lexcrypta.com (partner intake form on the homepage)
**Backup:** DM on Crypto Twitter — they're active there

> **Subject:** ZENTORY Labs pre-launch legal advisory inquiry — token classification + entity + T&C
>
> Hi Lex Crypta team,
>
> ZENTORY Labs is a non-custodial DeFi protocol on HyperEVM: ERC-4626 vaults
> running a transparent long/flat spot strategy (hold in uptrends, rotate to
> cash in downturns), an EIP-712 signed research/signal layer, and a
> governance/utility token (ZENT). Mainnet is gated on an external smart
> contract audit (being scoped now), a multisig migration, and a 3-month
> public track record — realistically ~Q1 2027, so counsel engaged now has
> comfortable runway.
>
> Looking to engage counsel for the pre-launch package:
>
> 1. **ZENT token classification opinion** — utility token under EU MiCA + relevant secondary jurisdictions (we plan to block US at launch)
> 2. **Entity structure review** — currently planning [BVI / Cayman — please advise] for the operating entity
> 3. **Founder liability shield review**
> 4. **Geographic restriction strategy** — what we need to block, how to enforce at the frontend, language for the T&C
> 5. **T&C, Privacy Policy, risk-disclosure review** — live drafts at zentorylabs.com need a crypto-native pass before mainnet (the current ToS already discloses testnet status, admin powers, and product risks honestly)
>
> **About the protocol:**
> - Public repo: https://github.com/Zentory-Labs/zentory-protocol
> - Whitepaper: https://www.zentorylabs.com/whitepaper
> - Testnet dApp: https://app.zentorylabs.com (live public track record + risk docs)
> - All contracts deployed to HyperEVM testnet (chain 998); mainnet (chain 999) post-audit
>
> We're prioritizing speed, cost predictability, and EU/MiCA fluency over US securities depth — which is why we're starting with you over the larger US firms. Budget expectation in the USD $25–50k range for the full package.
>
> Can you share:
> 1. Earliest engagement availability
> 2. Scope + indicative fee for the package above
> 3. A sample of a comparable engagement (DeFi protocol token opinion + entity)
>
> Happy to send a one-pager and book a 30-min intro call when convenient.
>
> Best,
> Edge
> Co-founder, ZENTORY Labs
> info@zentorylabs.com
> Telegram: @ZentoryEdge

---

## 4. Cooley LLP — Legal counsel (US fallback)

**Send only if you decide to onboard US users from day 1.** Skip if blocking US.

**Submit at:** https://www.cooley.com/services/practice/transactions/crypto (contact form on the practice page) or directly via your network if you have a partner referral.

> **Subject:** Engagement inquiry — ZENTORY Protocol pre-launch counsel, US securities + token classification
>
> Hi Cooley crypto team,
>
> ZENTORY Labs is a non-custodial DeFi protocol on HyperEVM (Hyperliquid's L1
> EVM): ERC-4626 drawdown-defense vaults, an EIP-712 signed research/signal
> layer, and a governance token (ZENT). Mainnet is gated on an external audit,
> multisig migration, and a 3-month public track record (~Q1 2027).
>
> We're scoping US securities counsel for the pre-launch package. Specifically:
>
> 1. ZENT token classification opinion under US securities laws (Howey, recent SEC guidance)
> 2. Path-to-launch evaluation for US user onboarding (Reg D 506(c) vs Reg S vs full retail blocking)
> 3. Entity structure review for the operating entity + ZENT token issuer
> 4. T&C, Privacy Policy, risk disclosure review
> 5. Engagement on bug bounty / Immunefi terms
>
> Codebase: 29 Solidity contracts, ~3.6k LOC, deployed to HyperEVM testnet; frozen audit branch + readiness package public. Smart contract audit being scoped in parallel.
>
> **Public docs:**
> - Repo: https://github.com/Zentory-Labs/zentory-protocol
> - Whitepaper: https://www.zentorylabs.com/whitepaper
> - dApp: https://app.zentorylabs.com
>
> Budget envelope: USD $75–150k for the package. Open to higher if your engagement model recommends additional scope.
>
> Three things to send back:
> 1. Earliest engagement slot
> 2. Proposed scope + fee range
> 3. Sample engagement summary from a comparable DeFi or token-launch matter
>
> Best,
> Edge
> Co-founder, ZENTORY Labs
> info@zentorylabs.com
> Telegram: @ZentoryEdge

---

## 5. QuickNode Support — HyperEVM RPC endpoint

**Email:** support@quicknode.com (or in-dashboard ticket if you have an account)

> **Subject:** Custom chain endpoint request — HyperEVM mainnet + testnet for production keeper
>
> Hi QuickNode Support,
>
> Looking to provision two dedicated RPC endpoints for HyperEVM, used by a production keeper bot + indexer + dApp.
>
> **Networks needed:**
> - HyperEVM testnet (chain ID 998) — `https://rpc.hyperliquid-testnet.xyz/evm`
> - HyperEVM mainnet (chain ID 999) — `https://rpc.hyperliquid.xyz/evm`
>
> **Estimated load (small / scale):**
> - Small TVL (now): ~12,000 RPC calls/day total across the stack
> - At $10M TVL: ~50,000 calls/day
> - Methods: eth_call, eth_getLogs, eth_sendRawTransaction, eth_blockNumber, eth_getTransactionReceipt, eth_estimateGas
>
> **Workload pattern:** mix of cron-triggered batches (every 4h + every 15m) and steady dApp reads via wagmi/viem.
>
> Tier preference: Build → Scale (~$50–200/mo range) with the option to upgrade as TVL grows.
>
> A few questions:
> 1. Can you provision a HyperEVM endpoint for our account? I see Hyperliquid isn't in the default catalog but I understand custom chains are supported.
> 2. What's the typical lead time?
> 3. Any per-method rate limits I should design for (especially eth_getLogs which the indexer hits in 1000-block batches)?
> 4. Do you have multi-region failover for custom chains, or is that on the standard chains only?
>
> Happy to share an architecture overview if useful.
>
> Best,
> Edge
> Co-founder, ZENTORY Labs
> info@zentorylabs.com

---

## What to do after sending

1. **Track responses in a spreadsheet** — even a simple Notion table with columns (firm, sent date, response date, scope quoted, fee quoted, status). 5 emails = no spreadsheet needed; 15+ outreach emails = you'll lose track without one.
2. **Set a 7-day follow-up** for each non-response. Polite bump, no apology — just "wanted to make sure this didn't get lost."
3. **Don't sign the first engagement** that comes back. Wait for 2+ quotes per category (audit + legal) so you have negotiating leverage.
4. **For the audit:** the proposal you sign is the first impression — read the sample report critically. Look for specific findings (not just CWE categories), severity reasoning, remediation review depth.

---

*Last updated: 2026-08-26 — refreshed to the 2026-08-21 `audit/2026-Q3b`
re-freeze @ `1f83fcbc`: 384-test suite across 38 files (was "344 tests, 34
files" from the 2026-06-12 freeze), Tier 0 remediation queue linked, honest
mainnet gating, and `info@zentorylabs.com` (the prior
`edge@zentorylabs.com` did not exist and would have bounced replies).*
