# ZENTORY — current state

Single-page status doc. Last updated 2026-05-26.

For investors evaluating the protocol, advisors getting up to speed, new
team members onboarding, or future-you wanting to remember where things
stood.

This is the workspace-root version that pulls together everything from the
three repos (`zentory-protocol`, `zentory-app`, `zentory-engine`) plus the
marketing site (`zentorylabs.com`). For repo-specific deep dives see each
repo's own README.

---

## TL;DR — where we are

- **Protocol:** 26 Solidity contracts deployed to HyperEVM testnet (chain 998). Public repo. Internal pentest + Slither complete. External audit being scoped.
- **dApp:** Live at app.zentorylabs.com. 20+ routes including signal arena, vault deposit/withdraw, dashboard, faucet. Demo mode + live mode supported.
- **Marketing site:** Live at zentorylabs.com. Whitepaper, tokenomics, /why competitor matrix, /roadmap, /faq, /contribute, /blog with 5 posts. Inline waitlist + Discord + Telegram all live.
- **Off-chain infra:** Keeper bot + heartbeat + indexer all running on Railway with Discord alerting + Sentry observability.
- **Token:** ZENT testnet deployed at `0x271cd48c1297CacCD810c7B1BCD904f459df7117`. Mainnet launch gated on audit completion.

---

## What investors should read first

1. **[Investor FAQ](zentory-protocol/docs/INVESTOR_FAQ.md)** — 10 questions, honest answers.
2. **[Whitepaper](https://www.zentorylabs.com/whitepaper)** — protocol architecture.
3. **[Tokenomics](https://www.zentorylabs.com/tokenomics)** + **[TGE structure](zentory-protocol/docs/TGE_STRUCTURE.md)** — distribution + vesting + buyback.
4. **[Roadmap](https://www.zentorylabs.com/roadmap)** — phase-by-phase path to mainnet.
5. **[Security audit brief](zentory-protocol/docs/SECURITY_AUDIT_BRIEF.md)** — scope + threat model.

Optional deep reads:

- [Why ZENTORY: verifiable vs trust-me](https://www.zentorylabs.com/blog/why-zentory-verifiable-vs-trust-me)
- [Inside epoch scoring](https://www.zentorylabs.com/blog/inside-epoch-scoring)
- [Why ERC-4626 matters](https://www.zentorylabs.com/blog/why-erc-4626-matters)
- [The HyperEVM bet](https://www.zentorylabs.com/blog/the-hyperevm-bet)
- [Tokenomics walked through](https://www.zentorylabs.com/blog/tokenomics-walked-through)
- [Inside StrategyExecutor](https://www.zentorylabs.com/blog/inside-strategyexecutor)

---

## Repo map

| Repo | License | What's in it | URL |
|---|---|---|---|
| `zentory-protocol` | BSL 1.1 | Solidity contracts + Foundry tests + audit brief + ops docs | https://github.com/Zentory-Labs/zentory-protocol |
| `zentory-app` | AGPL-3.0 | Next.js 16 dApp (app.zentorylabs.com), wagmi/viem, demo mode | https://github.com/Zentory-Labs/zentory-app |
| `zentory-engine` | Proprietary | Python signal engine, indexer, GP toolkit | https://github.com/Zentory-Labs/zentory-engine |
| `zentorylabs.com` | MIT | Next.js marketing site (zentorylabs.com), whitepaper, blog, FAQ | https://github.com/Zentory-Labs/zentorylabs.com |

---

## Live infrastructure

| System | Where | Status | Cost |
|---|---|---|---|
| Marketing site | Vercel (zentorylabs-com project) | ✅ Live at zentorylabs.com | Free tier |
| dApp | Vercel (zentory-token project — legacy name) | ✅ Live at app.zentorylabs.com | Free tier |
| Keeper bot (settler) | Railway, 4-hour cron | ✅ Live, settles epochs on EpochScoring | ~$5/mo |
| Keeper heartbeat | Railway, 30-min cron | ✅ Live, alerts Discord on settler failure | Bundled |
| Engine indexer (executor) | Railway, 15-min cron | ✅ Live, indexes StrategyExecutor events to Supabase | Bundled |
| Supabase | Cloud-hosted | ✅ Live, 7 tables + 1 RPC for keeper | Free tier |
| Sentry | sentry.io (zentory-labs org) | ✅ Live for dApp; tunnel proxy at /monitoring | Free tier |
| Discord webhook | Custom webhook URL | ✅ Live, heartbeat posts to #zentory-alerts | Free |

Total recurring infra cost: **~$5/mo** through testnet phase.

---

## Contracts on HyperEVM testnet (chain 998)

Source of truth: `zentory-protocol/DEPLOYMENTS.md`. Mirror in `zentory-app/lib/contracts.ts`. Marketing site updates on the same SHA.

| Category | Contract | Address |
|---|---|---|
| Token | ZENT | `0x271cd48c1297CacCD810c7B1BCD904f459df7117` |
| Token | ZENTVesting | `0xf7c45f45768d790F388215A44d6E01f6f2568774` |
| Vaults | zBTCVault | `0x93669daC07321FF397cf5734Ae8364EA24addF45` |
| Vaults | zETHVault | `0xbe8a9d22560A1b126554b70Aaca2D763B2E70C4e` |
| Vaults | zSOLVault | `0xb62BA9d0a14aC9f9601891179B3Da52bE71Ce052` |
| Vaults | zXRPVault | `0x8B15204D88a9Bb155bE6798522983A3B5F7d7cB0` |
| Staking | ZENTStaking | `0x4E2e7Fd3C85c05697b24743e580B03abCD6d0c65` |
| Staking | ModelBonding | `0x15f6c4bf4000747E0fDd85B33998A36F5BdF5007` |
| Governance | Timelock | `0x1504cA3C050C88CcCa67696d642F634fc381fD03` |
| Governance | Zentroller | `0x24f9401284CE16CFe61e40C1F9e3fb37d15B878E` |
| Governance | ZentGovernor | `0x21ba1F7C028B1ADc78e75Ac187B08b1BDd567118` |
| Execution | HyperCoreAdapter | `0xdad9175f6d2da1709ba3f73711e69022538d21a7` |
| Execution | StrategyExecutor | `0xacd862ef134d772b0ca53a97f53ccdd00abc05cf` |
| Signals | SignalRegistry | `0x7745B22B2C73E422154Fcd1ECD283765c4BF6e8c` |
| Signals | EpochScoring | `0xB6b206AaF3a482624238dD8292BB63EDBAf59143` *(redeployed 2026-05-25)* |
| Signals | SubscriptionVault | `0xd7d346f6d1F2CEcc3E67d9749B5121549F3dd80d` |

---

## Phase status

| Phase | Status | Detail |
|---|---|---|
| **Phase 0 — Foundation** | ✅ Complete | Testnet deployed. dApp live. Marketing site live. Keeper + indexer + observability running. |
| **Phase 1 — Security & Compliance** | 🟡 In progress | Audit + multisig + legal counsel all queued. Email drafts ready to send. |
| **Phase 2 — Mainnet & Token Launch** | ⏳ Planned | Q3–Q4 2026. Audit-gated. |
| **Phase 3 — Product Expansion** | ⏳ Planned | Q4 2026 – Q1 2027. Conviction Score + Ghost Portfolio UI. |
| **Phase 4 — Decentralization** | ⏳ Planned | 2027. Multi-chain + elected governance. |

---

## Active risks (live)

| Risk | Mitigation status | Owner |
|---|---|---|
| ZENT classification (US securities) | Block US at launch; legal counsel engagement ready to send | Legal counsel (M4) |
| Audit slipping past Q3 2026 | Three firms shortlisted (Cantina / ToB / Spearbit); outreach drafts ready | Audit (M2) |
| HyperEVM validator centralization | Mandate-bounded execution caps blast radius; not a hard blocker | Architecture |
| Keeper wallet compromise | Bounded by mandate; circuit breaker is permissionless | Ongoing |
| Vercel auto-deploy regression | Fallback GitHub Action shipped, dormant until secrets added | Ops |

---

## What's blocked on user action (founders) right now

1. **Send 3 outreach emails** (Cantina + Lex Crypta + QuickNode) — drafts in `zentory-protocol/docs/OUTREACH_EMAILS_READY_TO_SEND.md`
2. **Pick 5 signer addresses for multisig** (M3) — plan in `zentory-protocol/docs/MULTISIG_MIGRATION_PLAN.md`
3. **Decide US-blocked vs US-onboarded** for legal scope (M4)
4. **Confirm $250k POL budget** for HyperSwap seed pool (M7/M8)

Nothing else is blocked on internal work — the technical surface is at "send the emails and execute the launch sequence" state.

---

## Where to dig deeper

- **Contract source:** `zentory-protocol/contracts/src/`
- **Test suite:** `zentory-protocol/contracts/test/` (17 Foundry files)
- **Internal pentest:** `zentory-protocol/docs/reports/pentest-2026-04-26.md`
- **Slither output:** `zentory-protocol/docs/reports/slither-2026-04-26.json`
- **dApp routes:** `zentory-app/app/`
- **Marketing site routes:** `zentorylabs.com/app/`
- **All planning docs:** `zentory-protocol/docs/`

---

*Confidential financials, cap table, term-sheet specifics, and burn-rate detail are not in this doc. Available under NDA via edge@zentorylabs.com.*
