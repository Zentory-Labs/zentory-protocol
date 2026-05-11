# ZENTORY Labs — Team

*Last updated: May 2026.*

ZENTORY is built by a small, technically dense team. Each contributor below operates under a stable handle that is verifiable across GitHub, X, and (where applicable) LinkedIn. We list pseudonymous handles because that is how each contributor is identifiable across the work they have shipped — not because the protocol is anonymous in operation. Legal and ops counterparties at ZENTORY Labs are KYC'd and on record with security and audit partners.

For business inquiries: `contact@zentorylabs.io`.
For security disclosure: `security@zentorylabs.com` (see [`SECURITY.md`](SECURITY.md)).

---

## Core team

### Edge — Co-Founder, Head of Algo & Strategy

Edge leads algorithm design, strategy research, and execution infrastructure at ZENTORY. He owns the quant research lab in [`engine/`](engine), the genetic-programming / strategy modules, and the EIP-712 signing path that drives [`contracts/src/keeper/StrategyExecutor.sol`](contracts/src/keeper/StrategyExecutor.sol). His background spans quantitative research and systematic trading across asset classes, with a focus on risk-controlled, rules-based strategies. At ZENTORY Labs he drives the design of the crypto and L1 alpha models.

| Handle | Link |
|---|---|
| GitHub | [@edgeza](https://github.com/edgeza) |
| X | TBA — to be linked from [@ZENTORYLabs](https://twitter.com/ZENTORYLabs) once verified |
| Email | `edge@zentorylabs.io` |
| Public profile | [zentorylabs.com/team/edge](https://zentorylabs.com/team/edge) |

### Shaman — Co-Founder, Head of Operations & Public Relations

Shaman owns day-to-day operations, partner and community relations, and external communications. He oversees the public surface (marketing site, social, investor materials), the legal/compliance workstream (geo-blocking policy, regulatory memos, Immunefi setup), and partner integrations. His experience includes growth and go-to-market in technology and finance.

| Handle | Link |
|---|---|
| GitHub | TBA — to be linked from this README once active |
| X | TBA — to be linked from [@ZENTORYLabs](https://twitter.com/ZENTORYLabs) once verified |
| Email | `shaman@zentorylabs.io` |
| Public profile | [zentorylabs.com/team/shaman](https://zentorylabs.com/team/shaman) |

---

## Operating model

ZENTORY Labs operates as a small core team with bounded external contractors for:

- **External security audit** — engaged for the Q4 2026 mainnet gate (per [`docs/plans/2026-04-25-001-verification-master-plan.md`](docs/plans/2026-04-25-001-verification-master-plan.md)).
- **Bug bounty intake** — Immunefi (setup in [`docs/IMMUNEFI_SETUP.md`](docs/IMMUNEFI_SETUP.md)).
- **Legal counsel** — token-utility and securities-classification review (see [`docs/regulatory-memo.md`](docs/regulatory-memo.md)).

We do not operate a token-holder-facing fund. The protocol is the product.

---

## Verifiability checklist (for rating platforms and investors)

To verify the team:

1. **GitHub:** [`edgeza/ZentoryToken`](https://github.com/edgeza/ZentoryToken) owner. Commit history shows the active maintainer. The README points back to this `TEAM.md`.
2. **X:** [@ZENTORYLabs](https://twitter.com/ZENTORYLabs) is the canonical project handle. Founders' personal handles will be cross-linked from the project handle's bio once the handle is verified on the rating platform.
3. **Marketing site:** [zentorylabs.com/team](https://zentorylabs.com/team) — mirrors the bios above with the same handles. The site is the only public surface we control end-to-end.
4. **Email:** `*@zentorylabs.io` and `*@zentorylabs.com` resolve to ZENTORY Labs domain, which is the same brand as the marketing site, the dApp ([app.zentorylabs.com](https://app.zentorylabs.com)), and the X handle.
5. **Investor materials:** [`docs/INVESTOR_ONE_PAGER.md`](docs/INVESTOR_ONE_PAGER.md), [`docs/whitepaper.md`](docs/whitepaper.md), and [`STRATEGY.md`](STRATEGY.md) are signed off by the core team.

If you are evaluating this project and the verification chain above is incomplete on any platform, please email `contact@zentorylabs.io`; that is a docs / settings bug on our side and we will fix it.

---

## Hiring

Open contractor-style engagements are tracked at [zentorylabs.com](https://zentorylabs.com). Current priority hires:

- Senior Solidity engineer (vault & executor invariants, mainnet gate G1–G5 owner).
- Smart-contract auditor (external; for Q4 2026 audit window).
- Quant research contributor (signal author with verifiable track record; ZENT bond required).
- Frontend engineer (dApp, [`frontend/`](frontend), Next.js 16 + wagmi + viem).

Reach `contact@zentorylabs.io` with a portfolio link and a short note on which of [`STRATEGY.md`](STRATEGY.md) §5 tracks you want to own.
