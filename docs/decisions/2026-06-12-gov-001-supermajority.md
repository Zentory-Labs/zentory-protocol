# Decision GOV-001 — Governance supermajority

*Status: **ACCEPTED** (decided 2026-06-12; standing veto: Edge).*
*Implemented in `contracts/src/governance/ZentGovernor.sol::_voteSucceeded` (constant `SUPERMAJORITY_BPS = 6600`); 7 pinning tests in `contracts/test/governance/ZentGovernor.t.sol`.*

## Problem

The README and whitepaper §11 committed to a **66% supermajority** for protocol
upgrades, but `ZentGovernor` inherited `GovernorCountingSimple`'s default success
rule — a simple majority (For > Against). The published governance model and the
deployed code disagreed; the 2026-06-10 re-scan flagged this as GOV-001 and the
whitepaper additionally implied a two-tier model (simple majority for parameters,
66% for upgrades) that existed nowhere in code.

## Decision: uniform 66% supermajority for every proposal

`_voteSucceeded` now requires `For ≥ 66% of (For + Against)` for **all** proposals.
Abstain counts toward quorum (standard `GovernorCountingSimple` semantics) but not
toward the threshold. Quorum (15% of veZENT supply) and the 48h timelock are
unchanged and stack on top.

## Why uniform instead of the two-tier model the whitepaper sketched

1. **Classification is bypassable.** Tiering by proposal class requires classifying
   actions on-chain by target/selector. A proposal is an arbitrary batch of calls —
   wrap an upgrade-class call behind a passthrough or batch it with parameter
   changes and the classifier reads it as the lower tier. The mechanism designed to
   protect upgrades becomes the attack surface.
2. **One auditable invariant.** "No governance action passes under 66% of decisive
   votes + quorum + 48h timelock" is a single line an auditor can verify. A
   selector-routing table is a standing review burden on every new contract.
3. **The cost is acceptable.** The strict-direction error (parameters now need 66%
   instead of the whitepaper's simple majority) only makes governance *harder* to
   move — safety-biased, consistent with the drawdown-defense brand. Governance is
   near-dormant pre-TGE (veZENT supply ≈ 0) and parameter cadence post-TGE is low;
   routine ops do not flow through the Governor (admin behind timelock today, Safe
   after migration).
4. **Escape hatch exists.** If post-TGE practice proves the bar too high for
   routine parameters, governance itself can vote in a v2 governor with a tiered
   model — at 66%, which is exactly the bar such a structural change should clear.

Docs updated to match: whitepaper §11.1 table (all rows 66% + rationale), README
governance bullet, AUDIT_READINESS §3.6. Handed to the external auditor as a
decided design with its record.

## Boundary semantics (pinned by tests)

- Exactly 66.00% For **passes** (`forVotes × 10000 ≥ total × 6600`).
- 65% fails, 60% fails (the pre-fix regression case), 67% passes, unanimous passes.
- Zero For votes always fails; large Abstain does not dilute the threshold.
