# Fee Consolidation Plan

> Referenced by `MAINNET_READINESS.md` Tier 2 #7 and Tier 2 #9. Source: `contracts/src/fees/FeeDistributor.sol`, `contracts/src/signals/SubscriptionVault.sol`.

This document is the migration plan for consolidating all protocol fee revenue to a single recipient — the **Ecosystem Treasury Safe** at `0x0BD1EcD88C97572eeE77CbA4fE1008EC17E7e6c3` on HyperEVM mainnet (chain 999). The work has two parts: (a) verify the Safe is the single recipient on every fee-routing contract, and (b) sequence the work after the Safe migration so the admin key that points the distributors is itself a real 2-of-3 hardware multisig.

The numbers and the "cannot" column for governance come from `docs/TGE_STRUCTURE.md`: the **50/25/15/10** split (buyback+burn / Protocol Treasury / Insurance / Ops+GP engine) is the on-chain truth in `FeeDistributor.distribute()`. This plan does not change the split. It changes the **recipient** so the split lands in one auditable place.

---

## 1. Current State

### 1.1 `FeeDistributor` per vault

- Each vault (zBTC, zETH, zSOL, zXRP, and the post-Tier-0 SpotVault v2) has its own `FeeDistributor` instance.
- The distributor collects performance fees and routes them per the hardcoded 50/25/15/10 split:
  - **50% → buyback/burn** (sent to `ZENTBuyback.sol`, which swaps the underlying for ZENT on HyperSwap and burns to `0xdead`). This leg is not a recipient — it is a contract call.
  - **25% → `protocolTreasury` address** (set per-distributor in the constructor; mutable via `setProtocolTreasury(newProtocolTreasury)` gated by `GOVERNOR_ROLE`).
  - **15% → `insurance` address** (set per-distributor; currently the `insuranceFund` in the staking contract per self-audit finding note).
  - **10% → `gpEngine` address** (set per-distributor).
- Today, each distributor's `protocolTreasury` / `insurance` / `gpEngine` is whatever was passed into the constructor at deploy time. In practice this is one or two EOA-controlled addresses per role, **not** the Safe.

### 1.2 `SubscriptionVault` treasury

- `SubscriptionVault.sol` collects ZENT-denominated subscription revenue from signal tier subscriptions.
- The treasury is set in the constructor as `address treasury` (immutable today — no setter).
- `subscribe()` and `renewSubscription()` route ZENT to `treasury` via `zentToken.safeTransferFrom(msg.sender, treasury, totalCost)`.
- Today, `treasury` is set to an EOA address that is not the Safe. This is the **Tier 2 #7** blocker.

### 1.3 Why this is a problem

- Three (or more) different recipient addresses per vault, none of them a multisig.
- An attacker who compromises any one of those EOAs can reroute **that distributor's** slice of fees, even if the Safe is untouched. The blast radius is per-distributor, but the operational complexity of defending N addresses is real.
- Diligence: a technical investor running the whitepaper-vs-code diff finds multiple fee recipient addresses and asks why the protocol does not have a single, transparent, multisig-controlled recipient. The honest answer today is "we hadn't migrated yet."

---

## 2. Desired State

### 2.1 Single recipient

**Ecosystem Treasury Safe:** `0x0BD1EcD88C97572eeE77CbA4fE1008EC17E7e6c3` (HyperEVM mainnet, chain 999).

This Safe is the **single treasury address** the protocol uses for:

- The `protocolTreasury` leg of every `FeeDistributor` instance.
- The `treasury` address on `SubscriptionVault` (requires the setter, see §3.3).
- Eventually, the `insuranceFund` and `gpEngine` legs of every `FeeDistributor` instance — these are sub-treasuries that the Safe then routes onward per governance. (This is the Tier 2 #9 follow-on; out of scope for the Tier 2 #7 work in this document.)

### 2.2 What does NOT change

- **The 50/25/15/10 split.** Hardcoded in `FeeDistributor.distribute()`. Per `TGE_STRUCTURE.md` §"What can governance change?", this split is in the **cannot** column. Changing the split requires full redeploy + migration. Not in scope.
- **The buyback contract address.** 50% flows to `ZENTBuyback.sol` automatically; the Safe receives the 25% treasury slice and on-passes to ops + quant grants + insurance per its internal logic.
- **The per-vault distributor instance.** Each vault still has its own `FeeDistributor` — that is by design (so per-vault accounting is clean). What changes is the **recipient** on the distributor, not the distributor topology.

### 2.3 Why a single recipient

- **One auditable balance.** Anyone can read the Safe balance to verify the protocol's fee accumulation. With multiple recipients, the answer to "how much has the protocol earned this month?" requires reading multiple addresses.
- **One governance surface.** The 2-of-3 hardware multisig that controls the Safe is the only admin surface that needs to be defended. Every per-distributor `GOVERNOR_ROLE` setter becomes a less-load-bearing backstop.
- **One accounting policy.** Treasury diversification, insurance drawdowns, ops expenses — all flow through the Safe's internal logic, not through N independent EOA decisions.
- **One investor answer.** "Where do protocol fees go?" → "To the Ecosystem Treasury Safe at 0x0BD…e6c3, then onward per the published split." End of sentence.

---

## 3. Migration Plan

The plan is sequenced so that no admin key on the path from distributor to Safe is an EOA. Each step has a verification step that proves it landed before the next step begins.

### 3.1 Verify the Safe exists at the address

**Pre-condition.** Before any setter calls, confirm on-chain:

- Address `0x0BD1EcD88C97572eeE77CbA4fE1008EC17E7e6c3` on HyperEVM (chain 999) is a deployed Gnosis Safe (or compatible) contract.
- Threshold is **2-of-3**, and the three signers are hardware wallets (Ledger / Trezor / equivalent). Per `MAINNET_READINESS.md` Tier 1 #2, the Safe migration **must** be complete before this consolidation begins; that work is tracked in `docs/MULTISIG_MIGRATION_PLAN.md` and `docs/KEY_MANAGEMENT.md`.
- The Safe is not behind any proxy that could swap signers unilaterally.

If the Safe is not yet at the 2-of-3 hardware threshold, **stop** and re-sequence. This plan depends on Tier 1 #2.

**Verification artifacts:**

- Block-explorer link to the Safe deployment tx.
- Screenshot or on-chain read of the Safe's `getThreshold()` returning `2` and `getOwners()` returning three distinct addresses.
- A signed attestation from each signer confirming they control the address.

### 3.2 Update every `FeeDistributor.protocolTreasury`

For each vault's `FeeDistributor`:

1. **Verify the current `protocolTreasury`.** Read `FeeDistributor.protocolTreasury()` and confirm the current value.
2. **Build the setter transaction.** `setProtocolTreasury(0x0BD1EcD88C97572eeE77CbA4fE1008EC17E7e6c3)` — the new treasury address is the Safe.
3. **Execute via the multisig that holds `GOVERNOR_ROLE` on that distributor.** Note: if `GOVERNOR_ROLE` is currently an EOA, this step requires rotating `GOVERNOR_ROLE` to the Safe first. See §3.4 below.
4. **Verify the new `protocolTreasury`.** Re-read `FeeDistributor.protocolTreasury()` and confirm the new value.

**Per-vault list (to be expanded as new vaults ship):**

| Vault | Distributor address (TBD) | `protocolTreasury` set? | Verified on-chain? |
|---|---|---|---|
| zBTC (SpotVault v2) | TBD | � | ☐ |
| zETH (SpotVault v2) | TBD | ☐ | ☐ |
| zSOL (SpotVault v2) | TBD | ☐ | � |
| zXRP (SpotVault v2) | TBD | ☐ | � |

**Note on `setProtocolTreasury` vs `setTreasuryRecipient`.** The actual setter on `FeeDistributor` is `setProtocolTreasury(address newProtocolTreasury)` (`FeeDistributor.sol:181`), gated by `GOVERNOR_ROLE`. If a future version of the contract introduces a differently-named setter, the table above must be re-verified against the deployed bytecode.

### 3.3 Update `SubscriptionVault.treasury`

`SubscriptionVault.treasury` is currently **immutable** (set in the constructor, no setter). Per `MAINNET_READINESS.md` Tier 2 #7, this requires a code change: add a `setTreasury(address newTreasury)` setter gated by the appropriate role (recommended: `GOVERNOR_ROLE` or a dedicated `TREASURY_ADMIN_ROLE`).

**Steps:**

1. **Code change.** Add `setTreasury(address newTreasury)` with the appropriate access control. PR with the change, audited or self-audited at the same level as the surrounding code.
2. **Test on testnet.** Deploy a `SubscriptionVault` mock on HyperEVM testnet (chain 998), exercise `setTreasury`, verify subsequent `subscribe()` and `renewSubscription()` route to the new treasury.
3. **Deploy mainnet.** Mainnet deploy of `SubscriptionVault` with the new setter **or** an upgrade path if the contract were upgradeable — it is not (per `contracts/scripts/audit/self_audit_findings.md` I-1), so the mainnet path is deploy-new + migrate-state. Migrate existing subscribers and outstanding renewals to the new contract.
4. **Set the new treasury.** Call `setTreasury(0x0BD1EcD88C97572eeE77CbA4fE1008EC17E7e6c3)` via the multisig holding the role.
5. **Verify.** Subscribe with a test wallet; confirm the ZENT lands in the Safe.

**Why this is not "just call a setter."** The contract was deployed without a setter because immutability was the cheaper design choice at the time. Adding a setter is a policy decision (governance controls the treasury, not a deployer key), and it requires the audit and remediation discipline that the rest of Tier 0 demands.

### 3.4 Rotate `GOVERNOR_ROLE` to the Safe

For every `FeeDistributor` and (post-deploy) every `SubscriptionVault`:

1. **Verify current `GOVERNOR_ROLE` holder.** Read the access-control role for the role that gates `setProtocolTreasury` / `setTreasury`.
2. **If the current holder is an EOA:** rotate it to the Ecosystem Treasury Safe. The grant goes through the multisig (which is itself the new admin in the migrated deployment). Verify the old EOA loses access.
3. **If the current holder is already a Safe:** skip — just queue the setter calls through that Safe.

This step is independent of §3.2 / §3.3 in mechanism but is sequenced before them so that the calls that change the recipient are themselves multisig-controlled.

### 3.5 Verify end-to-end on-chain

After §3.2, §3.3, §3.4 land:

1. **Trigger a fee accumulation.** Either by performing a real trade that produces yield above the high-water mark, or by exercising the test path on testnet first and mirroring to mainnet.
2. **Call `distribute(vault)`** on each `FeeDistributor` via the keeper role.
3. **Verify the Safe balance increases by 25% of the distributed amount.** The 50% buyback and 10% / 15% legs go to their respective destinations; the 25% treasury leg lands in the Safe.
4. **Verify the Safe's transaction log** shows the inbound transfer with the expected `FeesDistributed` event emitted on the distributor.
5. **For `SubscriptionVault`:** trigger a subscribe + renew; verify the Safe receives the ZENT.

**Pass criteria:** every vault's distributor and the `SubscriptionVault` route their respective slices to `0x0BD…e6c3`. No EOA on the path. Document the on-chain evidence (tx hashes, block numbers, event logs) into the consolidation closeout note.

---

## 4. Sequencing

This plan **must happen AFTER** the Safe migration (Tier 1 #2). It is sequenced that way because:

- If the Safe is 3-of-3 hot keys on one machine, then any setter call from the Safe to update the recipient requires one of those hot keys. The point of consolidating to the Safe is so that the recipient is defensible; calling through an undefended Safe does not deliver that.
- If `GOVERNOR_ROLE` on a distributor is currently an EOA deployer key, rotating it to the Safe before the Safe is 2-of-3 hardware means the new role-holder is itself undefended. Same problem.

```
Tier 1 #2  Safe 3-of-3 hot → 2-of-3 hardware migration    [must complete first]
    │
    ▼
§3.1  Verify Safe exists at 0x0BD…e6c3 with 2-of-3 hardware
    │
    ▼
§3.4  Rotate GOVERNOR_ROLE on each FeeDistributor (+ post-deploy SubscriptionVault) to the Safe
    │
    ▼
§3.2  Call setProtocolTreasury(Safe) on every FeeDistributor
    │
    ▼
§3.3  SubscriptionVault code change (setTreasury setter), deploy, migrate, setTreasury(Safe)
    │
    ▼
§3.5  End-to-end on-chain verification
    │
    ▼
Tier 2 #9  Insurance and gpEngine legs follow the same pattern (next iteration)
```

The SubscriptionVault code change (§3.3) has the longest lead — it requires a PR, review, test, and a deploy-new + migrate-state cycle. Start it as soon as Tier 1 #2 lands, in parallel with §3.4 and §3.2.

---

## 5. Risks and Rollback

### 5.1 Risks

- **Wrong address.** A typo in the Safe address sends protocol fees to an irrecoverable address. Mitigation: the setter call is queued in the multisig with a simulated call first (`eth_call` from a forked node) before the live tx. Two-engineer review on the multisig queue.
- **Old EOA still has a role.** If `GOVERNOR_ROLE` was granted to multiple addresses and only the new one is rotated, the old EOA retains setter rights. Mitigation: enumerate all role holders before rotation, not just the most recent grant.
- **Migration gap.** Between the `setTreasury` call and the on-chain verification, there is a window during which fees could route to the wrong address if the call reverts silently. Mitigation: the on-chain verification is done within the same operational window; if verification fails, the setter call is reversed by a follow-up call setting back to the prior address.

### 5.2 Rollback

`setProtocolTreasury` and `setTreasury` are reversible — calling them again with the old address restores the prior state. The rollback procedure is:

1. **Detect.** The verification step (§3.5) catches a wrong recipient within minutes.
2. **Revert.** Queue a follow-up setter call in the multisig to restore the prior recipient.
3. **Verify.** Re-run §3.5 with the prior recipient; confirm the fees now route correctly there.
4. **Document.** The incident gets a postmortem via `docs/POSTMORTEM_TEMPLATE.md` regardless of severity, because fee-routing errors are SEV1 by default.

### 5.3 Out-of-scope risks

- A bug in the `FeeDistributor.distribute()` math itself is **not** this plan's responsibility. That is Tier 0 (code defects) and gets fixed at the source, not by changing the recipient.
- A governance decision to change the 50/25/15/10 split is **not** this plan's responsibility. That requires full redeploy + migration per `TGE_STRUCTURE.md`, not a recipient change.

---

## 6. Acceptance Criteria

The plan is "done" when **all** of the following are true and have on-chain evidence:

- [ ] The Ecosystem Treasury Safe at `0x0BD1EcD88C97572eeE77CbA4fE1008EC17E7e6c3` is 2-of-3 hardware-controlled on HyperEVM mainnet (chain 999).
- [ ] Every `FeeDistributor.protocolTreasury` returns the Safe address.
- [ ] `SubscriptionVault.treasury` returns the Safe address.
- [ ] `GOVERNOR_ROLE` on every `FeeDistributor` (and on `SubscriptionVault`, post-§3.3) is the Safe, not an EOA.
- [ ] End-to-end verification (§3.5) passes on at least one real fee-distribution cycle per vault.
- [ ] The investor-facing materials (whitepaper §6.4, investor one-pager, TGE structure doc) reflect the single-recipient reality. Per Phase D.9 of the go-to-market checklist, the fee-split numbers are consistent across all docs (50% buyback/burn · 25% Protocol Treasury · 15% Insurance · 10% Ops/GP engine).

When all boxes are checked, the protocol's fee-routing surface area collapses from "however many addresses are wired in today" to **one**. The next audit, the next investor update, the next incident, all reference the same address.

---

## 7. Cross-References

- `docs/MAINNET_READINESS.md` — Tier 1 #2 (Safe migration), Tier 2 #7 (fee-recipient setters), Tier 2 #9 (full fee routing → treasury Safe).
- `docs/MULTISIG_MIGRATION_PLAN.md` — the 3-of-3 hot → 2-of-3 hardware procedure that gates §3.1.
- `docs/KEY_MANAGEMENT.md` — hardware-wallet custody of the three signers.
- `docs/TGE_STRUCTURE.md` — the 50/25/15/10 split (cannot be changed by governance), buyback cadence.
- `contracts/src/fees/FeeDistributor.sol` — the setter is `setProtocolTreasury(address)`, gated by `GOVERNOR_ROLE`.
- `contracts/src/signals/SubscriptionVault.sol` — the current `treasury` is immutable; §3.3 adds the setter.
- `contracts/scripts/audit/self_audit_findings.md` — I-1 (contracts are not upgradeable) constrains the migration path.

---

*Last updated: 2026-08-20. Tracked under Phase D of the go-to-market checklist.*
