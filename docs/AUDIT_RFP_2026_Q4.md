# Zentory Labs — Smart Contract Audit Request for Proposal (RFP)

**RFP ID:** ZTL-RFP-2026-Q4-001
**Issued:** 2026-08-28
**Response deadline:** 2026-09-21 (rolling review; early replies prioritised)
**Engagement target start:** 2026-10-13 (latest; earlier preferred)
**Engagement type:** Fixed-scope smart-contract security audit (Tier-1 firm)
**Confidentiality:** This RFP and any proposal in response are confidential.
**Primary contact:** Edge (Co-founder), `edge@zentorylabs.com`
**Security contact:** `security@zentorylabs.com` (PGP available on request)

---

## 0. How to respond

Please reply with:

1. **Engagement slot** — earliest start date and expected duration.
2. **Team composition** — names and one-paragraph bios for the lead auditor
   and any supporting reviewers. We will not accept "TBD" or "rotating
   bench" for the lead.
3. **Sample report** — a recent public report from a comparable
   engagement (DeFi infra, 1–5k LOC, ERC-4626 or similar) for our review.
4. **Quoted fee** — single line item, USD, including all expenses and
   the post-report remediation re-review window (see §6.4).
5. **Out-of-scope statement** — what you explicitly will *not* review.
6. **Conflict-of-interest declaration** — any prior or current engagement
   with Hyperliquid, HyperEVM core, or with any competitor listed in
   §10 of our public-vs-private policy (`docs/PUBLIC_VS_PRIVATE.md`).

Proposals are reviewed on a rolling basis. We will sign with the
firm that best satisfies §7 (selection criteria), not on first-come.

---

## 1. About Zentory Labs

Zentory Labs is building a multi-asset quantitative research protocol
on HyperEVM. The protocol combines:

- **ERC-4626 alpha vaults** (BTC, ETH, SOL, XRP, HYPE) — users deposit,
  the protocol allocates to on-chain market-making and arbitrage on
  Hyperliquid via a custom adapter (`HyperCoreAdapter`).
- **EIP-712 signed signal registry** — quants submit directional or
  volatility signals with on-chain attestations; the registry hashes
  and timestamp-locks them before the underlying trade horizon.
- **Epoch-based scoring keeper** — a Solidity-side settlement layer
  resolves each epoch's accuracy, ranks submitters, and distributes
  ZENT token rewards based on merit (not staking weight).
- **ZENT utility + governance token** — ERC-20, no protocol-revenue
  staking rewards (deliberately structured to avoid "investment
  contract" classification under US securities law; see
  `docs/regulatory-memo.md`).
- **Treasury multisig** with timelock for any admin action.

The protocol is testnet-live (chain ID 998) with no production TVL.
Mainnet (chain ID 999) deployment is contingent on a clean paid audit
and bug-bounty program.

## 2. Why we're commissioning this audit

- Our **investor narrative** for the upcoming raise requires a Tier-1
  audit report. Hyperliquid LPs and token-purchasers all do this check.
- Our **internal threat model** is in `docs/SECURITY_AUDIT_BRIEF.md`
  §4; we want an external review of that model plus the contract
  surface it covers.
- Our **testnet audit refresh** (Q3 2026, internal) fixed several
  high-severity findings already; we want an independent firm to verify
  we did not regress on those fixes and to find what we missed.

## 3. Scope of audit

### 3.1 In scope (must audit)

All Solidity source files under `contracts/src/` in the repository at
the commit hash supplied at engagement kickoff (likely the latest
`main` commit as of 2026-10-01):

| Category | File | Approx LOC | Notes |
|---|---|---|---|
| Token | `ZENT.sol` | ~250 | ERC-20 + mint/burn hooks |
| Token | `ZENTVesting.sol` | ~120 | Linear vesting, revocable by multisig |
| Token | `ZENTBuyback.sol` | ~150 | Fee-funded buyback/burn |
| Treasury | `ProtocolTreasury.sol` | ~200 | Pull-payment, multisig-gated |
| Treasury | `FeeDistributor.sol` | ~150 | Splits fees 50/50 buyback/ops |
| Treasury | `MerkleDistributor.sol` | ~120 | Airdrop claims, sweep-to-zero |
| Staking | `staking/ZENTStaking.sol` | ~400 | Lock-period staking, drift clamps |
| Staking | `staking/ModelBonding.sol` | ~250 | Quant reputation bonding |
| Signals | `signals/SignalRegistry.sol` | ~350 | EIP-712, replay protection |
| Signals | `signals/EpochScoring.sol` | ~500 | Accuracy batch, ranking |
| Signals | `signals/SubscriptionVault.sol` | ~200 | Pay-per-signal access |
| Signals | `signals/SignalTypes.sol` | ~80 | Shared structs/errors |
| Vaults | `vaults/BaseVault.sol` | ~450 | ERC-4626 + leverage accounting |
| Vaults | `vaults/IVault.sol` | ~50 | Interface only |
| Vaults | `vaults/zBTCVault.sol` | ~80 | Asset-specific config |
| Vaults | `vaults/zETHVault.sol` | ~80 | Asset-specific config |
| Vaults | `vaults/zSOLVault.sol` | ~80 | Asset-specific config |
| Vaults | `vaults/zXRPVault.sol` | ~80 | Asset-specific config |
| Vaults | `vaults/zHYPEVault.sol` | ~80 | Asset-specific config |
| Keeper | `keeper/StrategyExecutor.sol` | ~600 | Trade execution, slippage checks |
| Keeper | `keeper/HyperCoreAdapter.sol` | ~350 | Hyperliquid L1 precompile interface |
| Governance | `ZENTGovernor.sol` | ~250 | OpenZeppelin Governor fork |
| Governance | `ZENTTimelock.sol` | ~120 | 48h delay on admin actions |
| Libraries | `libraries/*.sol` (4 files) | ~350 | SafeCast, fixed-point math |
| **Total** | **~5,200 LOC across 27 files** | | |

### 3.2 Also in scope (deployed bytecode + state)

- All contracts **as deployed on HyperEVM testnet (chain ID 998)** at
  the addresses pinned in `docs/MAINNET_READINESS.md` §3.
- Foundry tests under `contracts/test/` as **regression evidence** —
  we are not asking you to re-author them, but we want the auditor's
  read on whether the test coverage actually proves the fixes.
- Slither report at `docs/reports/slither-ci.json` — already gating
  CI; the auditor's view on Slither findings not yet triaged.
- Internal pentest report at `docs/reports/pentest-2026-04-26.md` —
  one-day pentest; review our triage and propose follow-up scope.

### 3.3 Out of scope (explicitly)

We do not expect, and will not pay for, reviews of:

- Vendored libraries under `contracts/lib/` (OpenZeppelin, forge-std).
- Hyperliquid L1 precompiles — they are external infrastructure.
- Off-chain code (`zentory-engine/`, keeper JS under
  `contracts/keeper/src/` beyond ABI-level correctness).
- Marketing site, dApp frontend (`zentory-app/`), Supabase schemas.
- Tokens or contracts we don't own or control.
- Any future V2 contracts not in this repo at kickoff.

If the auditor believes something in scope needs to be re-classified,
we want to know *before* the engagement starts.

## 4. Findings we want prioritised

The following are known concerns from our internal review; we want
external confirmation that our mitigations are sound:

1. **Phantom NAV in `BaseVault.totalAssets()`** — we removed MTM
   PnL from `totalAssets()` after discovering it could be inflated
   by adversarial price pushes. Tests now assert settle-able only.
   *Question:* is `getNavPerShareViewOnly()` (which still reflects
   MTM for dashboards and the circuit breaker) safe as a read-only
   path?
2. **Drift in `ZENTStaking.totalVeSupply` / `totalStaked`** — we
   added defensive clamps. Confirm clamps don't open a new grief
   vector (e.g., griefing via tiny lock amounts).
3. **CEI compliance in `HyperCoreAdapter.sendLimitOrder`** — we
   patched a `size == 0` revert on `reduceOnly` paths. Confirm no
   other call paths violate CEI.
4. **Fee-dust in `FeeDistributor.distribute`** — `buybackDust` is
   now an explicit return field. Confirm rounding direction is
   safe (rounds in protocol's favour, not the caller's).
5. **Keeper key compromise blast radius** — what happens if a
   single keeper EOA is compromised? Is the on-chain permission
   model tight enough?
6. **MerkleDistributor sweep-to-zero** — typo'd as `sweep` →
   typo'd `ZeroRecipient` error. Confirm no other zero-handling
   bugs.
7. **`MAX_SIGNAL_EXPIRY` cap** — we added a cap that rejects
   signals with expiry > some horizon. Confirm the cap value and
   the error message don't enable grief.
8. **Cross-contract reentrancy** — we believe we have no cross-
   contract reentrancy but want a manual review specifically on
   `StrategyExecutor → HyperCoreAdapter → SignalRegistry` paths.
9. **Signature replay across chains** — `SignalRegistry` uses
   `chainId` and `verifyingContract` in EIP-712 digests but we
   want an external confirmation.
10. **ERC-4626 deposit / redeem rounding** — confirm rounding
    direction is depositor-favourable at all share decimals.

## 5. Methodology expectations

We expect a methodology that includes, at minimum:

- **Manual line-by-line review** of every in-scope contract by a
  named senior auditor (≥3 years of ERC-4626 / DeFi infra audit
  experience).
- **Threat-modelling workshop** — a 2-hour joint session within
  week 1 to align on the attack surface (see §6.3 below).
- **Automated tooling** — at least one of Slither, Mythril, or
  Echidna, run by the firm against the in-scope bytecode, with
  findings triaged manually (i.e., not a "Slither said X, take
  it" report).
- **Property-based / fuzz testing** — preferred but not required;
  if not in the base scope, please quote as an add-on.
- **Differential review** of the Q3 internal-audit fix set
  (`docs/AUDIT_HANDOFF_2026_Q3.md`) to confirm no regression.
- **Daily written updates** during the active review week so we
  can fix Critical/High findings in parallel rather than at the
  end.
- **Final report** following a structure comparable to industry
  standard (Trail of Bits / Spearbit / OpenZeppelin format).
  Severity ratings must use CVSSv3.1 or a clearly equivalent scale.

## 6. Logistics

### 6.1 Code access

- A frozen `audit/2026-Q4-<firm>` branch will be created at
  engagement kickoff.
- The firm gets read access to that branch plus `main`, plus the
  Foundry broadcast logs at `contracts/broadcast/` (testnet only).
- The firm does **not** get access to `zentory-engine/` (proprietary).
  Where the engine interacts with on-chain contracts, we'll provide
  the ABIs and any off-chain assumptions in writing.
- All code access is logged; credentials rotated at engagement end.

### 6.2 Communication

- Private Telegram or Slack channel between the firm lead and our
  core team (max 4 people on our side).
- Daily async updates (a written message every business day).
- A weekly 1-hour sync call during the active review window.
- Issue tracker (GitHub private repo or Linear) for findings, with
  severity tags.

### 6.3 Threat-modelling workshop

We will host a 2-hour live session in week 1 covering:

- Protocol overview (15 min)
- Architecture walkthrough (30 min)
- Known risks we want the auditor focused on (15 min)
- Q&A (60 min)

Recorded for the firm's internal use only; not shared externally.

### 6.4 Remediation re-review

We commit to fixing Critical and High findings within 5 business
days of report delivery. The engagement should include a re-review
window of at least 5 business days where the firm's lead auditor
confirms the fixes are correct and don't introduce regressions.
This re-review is part of the base fee; please do not break it out
as a separate line item.

### 6.5 Public disclosure

- Pre-launch findings stay confidential until mainnet deployment
  or 90 days post-report, whichever is shorter.
- Post-launch, an executive summary of the report is published
  on `https://zentorylabs.com/security` with a downloadable PDF.
- Critical / High finding details that could enable exploitation
  may be redacted in the public version at the auditor's discretion,
  but the redacted version is still published (we don't suppress).

## 7. Selection criteria (weighted)

| Criterion | Weight | Notes |
|---|---|---|
| Quality of named lead auditor (track record) | 30% | Public reports list |
| Domain match (ERC-4626, signal markets, perp DEX) | 25% | Sample report comparable |
| Calendar fit (engagement start ≤ 2026-10-13) | 20% | Hard constraint |
| Quoted fee (USD 80–200k base) | 15% | Tiebreaker only |
| Reporting quality / structure | 10% | We care about this for investors |

## 8. Budget and payment terms

- Base engagement fee: USD 80,000 – 200,000, depending on team size
  and scope additions (fuzz testing, formal verification of
  invariants, etc.).
- Currency: USD. Payment in stablecoins (USDC on Ethereum or
  HyperEVM) is acceptable.
- Payment schedule: 30% on engagement signature, 40% on delivery
  of draft report, 30% on acceptance of final report + remediation
  re-review.
- Expenses: included in base fee. Out-of-pocket travel, hardware
  wallets, or testnet ETH are at our cost, paid on receipt.

## 9. What we provide

- Source access (see §6.1).
- Threat model and audit brief at
  `docs/SECURITY_AUDIT_BRIEF.md` and `docs/AUDIT_HANDOFF_2026_Q3.md`.
- Slither + internal pentest reports (already in repo).
- Test suite (Foundry, 17 files, ~5,500 LOC of tests).
- 48-hour response SLA on auditor questions during business hours.
- Direct contact for the lead auditor with the core team
  (4-person max).
- Testnet ETH for any deployment / verification work the firm
  needs to do (we'll airdrop on request).

## 10. What we don't provide

- Access to `zentory-engine/` (proprietary; the strategy moat).
- Access to mainnet deployer keys (none exist; we haven't deployed
  to mainnet).
- Access to investor KYC / financial information.
- Any commitment of future audit work; this RFP is single-engagement.

## 11. Calendar (target)

| Date | Milestone |
|---|---|
| 2026-08-28 | RFP issued |
| 2026-09-21 | Proposal deadline (rolling review starts 2026-09-07) |
| 2026-09-30 | Firm selected, MSA + NDA executed |
| 2026-10-06 | Code freeze on `audit/2026-Q4-<firm>` branch |
| 2026-10-13 | Engagement kickoff + threat-modelling workshop |
| 2026-11-10 | Draft report delivery |
| 2026-11-13 | Audit findings internal triage complete |
| 2026-11-20 | Critical/High remediations landed |
| 2026-11-25 | Remediation re-review complete |
| 2026-11-30 | Final report signed off + public summary drafted |
| 2026-12-15 | Bug-bounty program live (Immunefi or similar) |

If the firm cannot meet the 2026-10-13 kickoff target but can meet a
date within 2 weeks of it, please still propose — we can flex our
calendar.

## 12. Submission

Send the proposal package (PDF + raw markdown OK) to:

- Primary: `edge@zentorylabs.com` (PGP key on request)
- Security back-up: `security@zentorylabs.com`

Subject line: `ZTL-RFP-2026-Q4-001 — <Firm Name> proposal`

Reply within 5 business days acknowledging receipt. We will reply to
substantive questions within 2 business days. We will sign with one
firm only; we may use a second firm for a targeted re-review if the
lead auditor's findings suggest an independent check.

---

*This RFP is confidential. Do not redistribute the contents or the
attached brief without written permission from Zentory Labs.*
