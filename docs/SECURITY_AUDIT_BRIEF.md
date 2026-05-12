# ZENTORY Labs — Smart Contract Security Audit Brief

**Prepared:** April 2026
**Contact:** [your email / Discord]
**Repository:** https://github.com/Zentory-Labs/zentory-protocol

---

## 1. Project Overview

ZENTORY Labs is a multi-asset quantitative research protocol deployed on HyperEVM. The protocol combines on-chain signal trading, ERC-4626 vault infrastructure, and a governance staking mechanism to create a closed-loop quant research marketplace. Quantitative researchers submit signals via SignalRegistry, which are scored by EpochScoring based on prediction accuracy. Top-ranked quants earn ZENT token rewards through a merit-based distribution mechanism. Users deposit assets into ERC-4626 vaults (BTC, ETH, SOL, XRP, HYPE) which are traded by keepers using a proprietary premium/discount algo (HyperCoreAdapter) on Hyperliquid. Fee revenue flows from vault trading into ProtocolTreasury, which splits yields 50/50 between ZENT buyback/burn and operations — creating a continuous demand sink for ZENT.

The protocol matters because it is one of the first attempts to tokenize quant research alpha in a permissionless, on-chain format — aligning researcher incentives directly with protocol revenue. The ZENT token serves as the governance token, staking asset, and fee-reclamation mechanism simultaneously.

---

## 2. Scope of Audit

### In Scope (contracts to audit)

All Solidity source files under `contracts/src/`:

```
contracts/src/
  ZENT.sol
  ZENTVesting.sol
  ZENTBuyback.sol
  ProtocolTreasury.sol
  FeeDistributor.sol
  ZENTStaking.sol
  staking/
    ZENTStaking.sol
    ModelBonding.sol
  signals/
    SignalRegistry.sol
    EpochScoring.sol
    SubscriptionVault.sol
    SignalTypes.sol
  vaults/
    BaseVault.sol
    IVault.sol
    zBTCVault.sol
    zETHVault.sol
    zSOLVault.sol
    zXRPVault.sol
  keeper/
    StrategyExecutor.sol
    HyperCoreAdapter.sol
  governance/
    ZentGovernor.sol
    Zentroller.sol
    Timelock.sol
  interfaces/
    IZENT.sol
    IZENTStaking.sol
    ISignalRegistry.sol
    IFeeDistributor.sol
```

### Out of Scope

- Frontend (Next.js app at `frontend/`)
- Backend (Supabase — treated as third-party)
- Keeper scripts (`contracts/keeper/`)
- Any third-party token integrations (USDC, WBTC, WETH, etc.)
- Engine trading logic (`engine/` Python package)

---

## 3. Architecture Overview

**ZENT Token Flow:** ZENT is the core utility and governance token of the protocol. It is staked via ZENTStaking to participate in governance (via ZentGovernor + Zentroller). Fee revenue is generated continuously from vault trading activity and flows into ProtocolTreasury, which distributes 50% to ZENTBuyback (buyback + burn to 0xdead) and 50% to operations. This creates a continuous demand-side pressure on ZENT, with the burn rate tied directly to protocol usage rather than discretionary governance decisions.

**Vault Architecture:** ZENTORY's vaults are ERC-4626 compliant wrappers around asset-specific strategies. Users deposit L1 assets (e.g., WBTC, WETH) and receive vault shares. Keepers (external bots) execute trades via HyperCoreAdapter and HyperliquidAdapter, capturing premium/discount spreads on each trade. The strategy executor can open and close positions on Hyperliquid; vault share price reflects cumulative trading performance. Circuit breakers exist as a permissionless pause mechanism that any address can trigger.

**Signal & Scoring Architecture:** Quants submit signals (predicted price movements) to SignalRegistry, signed with EIP-712. Signals are scored after each epoch settles (by the EPOCH_SETTLER role) based on actual vs. predicted outcomes. Top-ranked quants receive ZENT token rewards from a reward pool. This creates a competitive quant tournament with real economic stakes.

**Key Integrations:** HyperEVM (chain), Hyperliquid (perpetuals DEX), Supabase (off-chain data — wallet auth, user profiles, leaderboard), and OpenZeppelin Contracts 5.x (security primitives). The HyperCoreAdapter is a private algorithm — auditors should treat it as a black box and focus on how it interacts with the vault (input validation, slippage, access control) rather than the algorithm itself.

---

## 4. Critical Risk Areas

### 4.1 Access Control

ZENTORY uses OpenZeppelin's `AccessControl` for role-based permissions across all contracts. Key roles include:

- `KEEPER_ROLE` — granted to keeper bots that execute vault trades via StrategyExecutor and HyperCoreAdapter
- `EPOCH_SETTLER` — permissioned role that closes an epoch and triggers scoring in EpochScoring
- `SCORING_ORACLE` — role that feeds actual price outcomes into the scoring system
- `GOVERNOR_ROLE` — controls protocol parameters (fees, vault caps, signal stake thresholds)
- `TIMELOCK_ADMIN` — controls the Timelock itself (has a multi-step delay on governance actions)

Roles are assigned in constructors or by an admin address at deployment. Notable public (unrestricted) functions include: `checkCircuitBreaker()` (permissionless trigger), signal submission (anyone can submit, but must stake ZENT), and epoch voting (open to stakers). Auditors should verify that no privileged function can be called with replayed or expired signatures, and that role transfers are two-step with timelock delays.

### 4.2 Fee Distribution (FeeDistributor → ProtocolTreasury → ZENTBuyback)

Fees flow through a three-contract pipeline:

```
Vault trade fees → FeeDistributor.accumulate()
  → FeeDistributor.distribute()
    → ProtocolTreasury (receives fees)
      → ProtocolTreasury.distribute()
        → 50% ZENTBuyback (buyback → 0xdead burn)
        → 50% operations treasury
```

`FeeDistributor.distribute()` can be called by anyone (non-discretionary), preventing governance from blocking buybacks. The split ratio (50/50) is hardcoded and immutable. The primary audit focus should be: (a) does `accumulate()` correctly account for fees from multiple vaults? (b) can `distribute()` be called repeatedly to drain fees? (c) is the ProtocolTreasury split calculation exact (no rounding loss going to zero)? (d) can ZENTBuyback be bricked if the ZENT token is paused?

### 4.3 Vault Security (BaseVault, SubscriptionVault, z*Vault)

Vaults manage real user funds and are the highest-value attack surface:

- **Non-reentrancy guards:** `recordTrade()` and `closePosition()` use OpenZeppelin `nonReentrant` modifiers. Auditors should verify every external call path through these functions.
- **Circuit breakers:** `checkCircuitBreaker()` is fully permissionless — any address can trigger it. This is a design choice that favors safety over liveness. Audit question: can an attacker permanently prevent vault operations by front-running any deposit with a circuit breaker trigger?
- **Slippage protection:** All Hyperliquid orders should include slippage parameters validated in HyperCoreAdapter. Audit question: are these parameters user-configurable or hardcoded? If hardcoded, can MEV extract value?
- **Max TVL per strategy:** The BaseVault should enforce per-strategy TVL caps. Audit question: do these caps persist across epochs, or can a single large deposit bypass them?
- **SubscriptionVault:** A separate vault for signal-tier subscriptions. Verify that fee payment correctly gates access and that non-subscribers cannot receive signal-protected trades.

### 4.4 Epoch Scoring

Epoch scoring determines quant rewards — a high-stakes calculation that attackers may try to manipulate:

- **Permissioned epoch settlement:** Only `EPOCH_SETTLER` can call `settleEpoch()`. Verify the role is properly gated and cannot be transferred to an attacker.
- **Signal accuracy calculation:** Scored against actual HyperEVM price data fed by `SCORING_ORACLE`. Audit question: is the oracle data sourced from a single point, or aggregated? Can the oracle report stale prices?
- **Rank manipulation risk:** A well-funded attacker could stake ZENT, submit deliberately accurate signals in the last epoch, and then withdraw. Lock periods and epoch timing should be verified.

### 4.5 Signal Registry

Signals are the core intellectual property submitted on-chain by quants:

- **EIP-712 signature verification:** All signal submissions require a valid EIP-712 signature. Verify domain separation is correct (chain ID, contract address), and that signatures cannot be replayed across epochs or from other vaults.
- **Minimum stake requirement:** Signal submitters must stake ZENT as a bond, returned (in full or in part) upon scoring. Verify that: (a) stake is correctly locked during the signal window; (b) slashing logic cannot drain more than the submitted stake.
- **Publicly visible signals:** No privacy mechanism — all signals are on-chain. This is by design; do not assume signal content is confidential.

### 4.6 Flash Loan / Price Manipulation

A sophisticated attack vector for a protocol that combines staking, scoring, and vault trading:

- **Risk scenario:** Attacker stakes a large ZENT amount before an epoch, then uses flash loans to manipulate the price of a vault asset, making their signals appear accurate. After epoch scoring and reward distribution, they withdraw and unwind positions.
- **Mitigations in place:** ZENTStaking has lock periods (verify epoch timing aligns with lock expiry). Signal stake provides an economic deterrent.
- **Remaining exposure:** Auditors should assess whether the lock period is long enough relative to epoch duration to prevent the described attack. Also assess whether Hyperliquid's own liquidity is sufficient to make large price manipulations expensive.

### 4.7 Oracle Risk

- Price data for scoring is fed via the `SCORING_ORACLE` role. Auditors should determine: what is the primary price source? Is it a push or pull model? Can the oracle report prices for assets not traded on Hyperliquid? What happens if the oracle misses a price update for an epoch?
- HyperCoreAdapter itself may use an internal price feed for its premium/discount calculation — this should be treated as part of the audit scope since it affects vault share price.

---

## 5. Test Coverage

- **Current test count:** 18 Solidity test files under `contracts/test/`
- **Test framework:** Foundry (`forge`) — see `contracts/foundry.toml`
- **Coverage tool:** No Slither detector-based coverage tool is installed. An internal Slither run was conducted on 2026-04-26 (`docs/reports/slither-2026-04-26.json`) yielding **180 total findings** (37 high/medium severity).
- **Invariant testing:** None currently in place.
- **Recommended for audit firm:** Expand to formal invariant testing (e.g., via Foundry's `forge invariant`).

---

## 6. Known Issues / Acknowledge Risks

The following issues are known and intentionally not fixed:

1. **Slither finding: `arbitrary-send-erc20` in FeeDistributor** — FeeDistributor uses `safeTransferFrom` with an arbitrary `from` address in `accumulate()`. This is used by design (vaults accumulate fees). Acceptable because the caller must be an authorized vault contract; however, auditors should verify no vault can be injected by a malicious actor.
2. **Slither finding: `arbitrary-send-eth` in Governor/TimelockController** — These are inherited from stock OpenZeppelin Contracts 5.x. Not modified by ZENTORY. Low risk as they require governance approval.
3. **Permissionless `checkCircuitBreaker()`** — Anyone can trigger the circuit breaker. This intentionally favors safety over liveness but means an attacker can cause temporary vault unavailability (DoS). Considered acceptable: vaults can be resumed by a governor call.
4. **Signals are publicly visible** — No confidentiality for submitted signals. By design for a transparent quant tournament. Quants should not submit signals they wish to keep proprietary.
5. **`ZENTBuyback` burn relies on ZENT not being paused** — If ZENT is paused (admin action), buyback halts and fee flow to 0xdead stops. This is an acceptable trade-off: admin can pause ZENT in an emergency, which takes precedence over burn continuity.

---

## 7. Previous Audits

No formal third-party audit has been conducted on this codebase as of April 2026. An internal Slither static analysis run was performed on 2026-04-26 with 180 findings (37 high/medium severity). Findings have been reviewed but not yet remediated. This audit brief is the first step toward engaging a formal audit firm.

---

## 8. Compliance Notes

- **ZENT token classification:** ZENT is a utility token used for staking, governance, and fee payment. It is not marketed as a security. The protocol team has not sought legal opinions on token classification in any jurisdiction.
- **Geo-blocking:** Implemented at the application layer for US and OFAC-prohibited jurisdictions. Note: on-chain contracts cannot enforce geo-blocking — this is frontend-only.
- **KYC:** No KYC is required. Access is wallet-based pseudonymous.
- **ERC-4626 compliance:** Vaults implement the ERC-4626 standard for vault share token compatibility, enabling integration with aggregators and other ERC-4626-aware protocols.
- **Tax treatment:** Not reviewed. Users and quants are responsible for their own tax obligations in their respective jurisdictions.

---

## 9. Desired Audit Type

**Recommend: Two-phase audit**

- **Phase 1 (2 weeks):** Access control and role permissions, vault security (non-reentrancy, slippage, circuit breakers), fee distribution flows (FeeDistributor → ProtocolTreasury → ZENTBuyback), and reentrancy attack surface across all contracts. This phase covers the highest-value and highest-risk areas.
- **Phase 2 (2 weeks):** Full protocol review — epoch scoring, signal registry, oracle risk, governance contracts (ZentGovernor, Zentroller, Timelock), staking mechanics, and integration testing (HyperEVM, Hyperliquid, Supabase). Deliver final audit report at the end of this phase.

Firms may propose an alternative structure based on their assessment of the codebase.

---

## 10. Timeline

- **Target audit start:** Flexible — minimum **2 weeks notice** before desired start; prefer start after internal review of Slither findings
- **Target mainnet launch:** TBD — audit completion is a prerequisite
- **Can provide:** Testnet contract addresses, deployment transaction hashes (available in `contracts/broadcast/`), full codebase access (including private forks if needed), and a technical walkthrough call with the protocol team
- **Report delivery expectation:** Draft report within 10 business days of phase end; 5 business days for fact-check responses

---

## 11. Budget

[FIRM TO PROPOSE]

Indicative range for a two-phase full audit of a protocol of this complexity: **USD $30,000 – $60,000**. Final budget to be agreed upon proposal. Payment terms: 50% on engagement, 50% on draft report delivery.

---

## 12. Contact & Next Steps

- **Email:** [your email]
- **Discord:** [your Discord handle]
- **GitHub:** github.com/Zentory-Labs/zentory-protocol
- **Paperclip (dashboard):** http://localhost:3100/ZEN/dashboard

**Next steps:**
1. Share this brief with selected audit firms (Sigma Prime, Trail of Bits, OpenZeppelin, Spearbit, CodeHawks)
2. Receive and review proposals (scope, timeline, budget)
3. Select firm and agree on engagement terms
4. Grant repository access and schedule kickoff call
5. Provide deployment artifacts, architecture diagrams, and any additional context the firm requests

---

*This brief is confidential. Please do not share without ZENTORY Labs written consent.*
