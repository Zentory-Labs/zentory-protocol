# Security Policy

*This document is the public security policy of the ZENTORY Protocol. It covers responsible disclosure, scope, severity classification, safe harbor, and the contact channels for security researchers.*

---

## Reporting a vulnerability

If you have found, or suspect you have found, a security vulnerability in the ZENTORY Protocol:

1. **Do not** open a public GitHub issue, pull request, or Discussion describing the vulnerability.
2. **Do not** discuss the vulnerability in public chat (Telegram, Discord, X, etc.) before it is patched and disclosed.
3. **Do** send a report through one of the channels below.

### Reporting channels

| Channel | When to use |
|---|---|
| Immunefi: [`immunefi.com/project/zentory`](https://immunefi.com/project/zentory) | Preferred for in-scope contract vulnerabilities once the bug bounty program is live (mainnet). Provides structured intake, payout, and triage. |
| Email: `security@zentorylabs.com` | Anything else — testnet issues, infrastructure, dApp, marketing site, suspected key compromise. Always available, even before Immunefi goes live. |
| Encrypted email (optional) | PGP key on request via the same address. Reply within 24 hours. |

When in doubt, email is the catch-all. We would rather receive a report we are not sure how to triage than miss one.

### What to include

Please include, to the extent you can:

- A clear description of the vulnerability and the affected component.
- A proof of concept (transaction hash on testnet, Foundry test, script, screenshot).
- Your estimate of severity (see rubric below).
- A way for us to reach you for follow-up questions.
- Your preferred attribution (handle, real name, anonymous).

---

## Response timeline

The maintainer team commits to the following service levels. These apply once a complete report has been received via one of the channels above.

| Phase | Timeline |
|---|---|
| Acknowledgement of report | within 24 hours |
| Severity assessment + triage | within 7 days |
| Patch shipped (Critical / High) | within 30 days |
| Patch shipped (Medium / Low) | within 90 days |
| Public disclosure after patch | coordinated with reporter, typically 30-60 days post-fix |

If you do not hear from us within 24 hours of submission, please assume the email was lost in transit and try the alternate channel above.

---

## Scope

### In scope

The following components are in scope for the ZENTORY Protocol security policy:

- **Smart contracts** in [`contracts/src/`](contracts/src) — token, vaults, staking, signals, governance, executor.
- **Deployed contracts** listed in [`DEPLOYMENTS.md`](DEPLOYMENTS.md) on HyperEVM testnet (chain ID 998) and, post-launch, on HyperEVM mainnet.
- **Epoch settlement keeper** in [`contracts/keeper/`](contracts/keeper) (TypeScript) — only logic that can affect on-chain state.
- **CI / build supply-chain risks** in [`.github/workflows/`](.github/workflows) — e.g. a workflow that could leak a deploy key, ship a poisoned dependency, or push a forged release tag.
- **Public protocol documentation** in this repository ([`docs/whitepaper.md`](docs/whitepaper.md), [`README.md`](README.md), [`STRATEGY.md`](STRATEGY.md)) — only material factual claims about the protocol that, if wrong, could mislead a depositor (e.g. "this fee is 15%" when the on-chain config is different).

### Out of scope

The following are explicitly **out of scope** for this policy:

- Third-party libraries vendored under [`contracts/lib/`](contracts/lib) (OpenZeppelin, forge-std). Report vulnerabilities in those to their respective maintainers.
- The marketing site at [zentorylabs.com](https://zentorylabs.com) — report via email but it is not part of the protocol attack surface.
- The dApp at [app.zentorylabs.com](https://app.zentorylabs.com). Report dApp-specific bugs to the [`Zentory-Labs/zentory-app`](https://github.com/Zentory-Labs/zentory-app) repository.
- Social engineering, phishing, physical attacks against contributors, or attacks that rely on a contributor's personal account being compromised.
- The internal research engine (private repository, not published).
- "Best practice" findings without a demonstrable security impact (e.g. "consider using a different naming convention"). These can still be raised as a normal GitHub issue.
- Findings that require unrealistic assumptions (e.g. "if the deployer's private key is stolen, the system can be drained").
- DoS via griefing of public-permissionless functions that have intentionally been left open (e.g. anyone can submit a signal — flooding with spam is expected and is bounded by the staking + slashing mechanism).

If you are unsure whether something is in scope, email `security@zentorylabs.com` and ask. We would rather discuss it than have you discard a finding.

---

## Severity classification

We use a 4-tier severity model. The classification of each finding is set by the maintainer team in consultation with the reporter and any external auditor we have engaged.

| Severity | Definition | Example |
|---|---|---|
| **Critical** | Direct, reproducible loss of user funds or protocol funds; unauthorized minting / burning of ZENT; bypass of the executor mandate that exceeds Solidity-enforced position or leverage caps. | A reentrancy that lets an attacker drain `BaseVault`. A signature bypass in `StrategyExecutor` that lets an attacker submit a signal as the authorized signer. |
| **High** | Significant loss conditional on attacker action; permanent locking of user funds; griefing that breaks core protocol invariants. | A bug that causes vault share redemption to revert permanently for one or more depositors. An invariant violation that desynchronizes `EpochScoring` from the registry. |
| **Medium** | Bounded financial impact; loss requires unusual conditions or significant prerequisites; protocol parameter misconfiguration that can be exploited but does not directly steal funds. | A rounding error that causes a small (<1%) loss on redemption under specific input shapes. |
| **Low** | No direct financial impact but a real security weakness; defense-in-depth gap; missing event emission, missing input validation that does not currently propagate. | An admin function missing a redundant check that is enforced one layer up. |

The maintainer team reserves the right to adjust the severity of a finding once full triage is complete. The reporter will be notified of any change.

---

## Bug bounty program

| Item | Status |
|---|---|
| Internal triage of reports | **Active** today, on testnet and pre-launch infrastructure |
| Coordinated disclosure timeline | **Active** today (see Response timeline above) |
| Monetary bounty payouts | **Pending Immunefi launch at mainnet** (target Q4 2026 per [`STRATEGY.md`](STRATEGY.md)). Bounty range and payout terms will be published on Immunefi and linked here once finalized. |
| Hall of Fame | Maintained from launch; reporters of valid issues will be acknowledged (with consent) at [`SECURITY_HALL_OF_FAME.md`](SECURITY_HALL_OF_FAME.md) once that file is seeded. |

Pre-launch (i.e. now): we do not pay bounties yet, but **all valid findings will be acknowledged publicly with the reporter's consent and counted toward early Hall of Fame credit, which carries weight into the live program**. Reporters who help us before launch are explicitly invited into the private testnet program with priority access.

---

## Safe harbor

ZENTORY Labs commits to the following safe harbor for security researchers who act in good faith:

1. We will **not pursue or support legal action** against you for research conducted under this policy, provided you:
   - Do not exploit a finding beyond what is necessary to confirm it.
   - Do not access, modify, or exfiltrate user data, private keys, or financial assets beyond your own.
   - Do not perform denial-of-service attacks beyond a brief proof of concept.
   - Do not test against mainnet or third-party accounts other than your own.
   - Report the finding through one of the channels above and give us a reasonable window to fix before public disclosure.
2. We will **not retaliate** for good-faith disclosure, including delaying, downgrading, or denying bounty for findings that are inconvenient.
3. If a law-enforcement or third-party demand reaches us about a security researcher whom we have confirmed acted in good faith, we will inform the researcher, retain counsel, and resist the demand to the extent the law permits.

This safe harbor does not extend to:

- Research conducted on assets you do not own (other users' wallets, other dApps' contracts).
- Trading, front-running, or any activity that monetizes a not-yet-patched finding before disclosure.

---

## Public disclosure policy

After a vulnerability has been patched:

- We will publish a security advisory in this repository (`Security` tab → `Advisories`).
- The advisory will credit the reporter (with consent) and link to the fix commit.
- Where the issue affected deployed contracts, the advisory will state which addresses were affected and the on-chain remediation step taken.
- Where the issue affected published docs, the advisory will link the corrected version.

We aim to publish the advisory within **30 days** of the patch being shipped, unless the reporter requests a longer embargo.

---

## Audit history

| Date | Type | Report |
|---|---|---|
| 2026-04-26 | Internal pentest | [`docs/reports/pentest-2026-04-26.md`](docs/reports/pentest-2026-04-26.md) |
| 2026-04-26 | Slither static analysis | [`contracts/slither_report.json`](contracts/slither_report.json) |
| Q3 2026 (planned) | External smart-contract audit | _firm and report TBA — published in this table_ |
| Q4 2026 (planned) | Mainnet deployment + public audit publication | _per [`STRATEGY.md`](STRATEGY.md)_ |

The verification master plan (gates G1-G10 with explicit acceptance criteria) is at [`docs/plans/2026-04-25-001-verification-master-plan.md`](docs/plans/2026-04-25-001-verification-master-plan.md). External audit is one of the G-gates between testnet and mainnet — there is no path to mainnet that does not go through a qualified external auditor.

---

## Operational contacts

| Purpose | Contact |
|---|---|
| Security disclosure (preferred) | `security@zentorylabs.com` |
| Bug bounty intake (post-launch) | [`immunefi.com/project/zentory`](https://immunefi.com/project/zentory) |
| Business / partnership / legal | `contact@zentorylabs.io` |
| General questions about the protocol | [GitHub Discussions](https://github.com/Zentory-Labs/zentory-protocol/discussions) |

---

*Last updated: May 2026. This policy is versioned with the repository; the current `main` branch is the canonical version.*
