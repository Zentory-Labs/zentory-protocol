---
title: "feat: Build Zentory Protocol — Smart Contracts, GP Engine, and Frontend"
type: feat
status: active
date: 2026-04-24
origin: whitepaper/page.tsx (Zentory Protocol Whitepaper v1.0)
---

# Build Zentory Protocol: Smart Contracts, GP Engine, and Frontend

## Overview

Build the full Zentory Protocol end-to-end: a non-custodial evolutionary alpha network on Hyperliquid with ERC-4626 benchmark-denominated vaults, ZENT utility token with buyback/burn, and an off-chain genetic programming engine for strategy generation.

This is a greenfield project. Only the whitepaper (`whitepaper/page.tsx`) exists. Everything else must be built.

---

## Problem Frame

Zentory's mission: let anyone hold ZENT or vault shares (zBTC/zETH/zSOL/zXRP) and outperform passive HODL of the underlying asset. The protocol combines genetic programming for strategy evolution, ERC-4626 vaults for benchmark-denominated alpha delivery, and a ZENT token with deflationary mechanics for protocol-level value capture.

**Critical constraints from the whitepaper:**
- Vault strategies are trend-following: buy at discount / sell at premium; long in bull regimes, cash/USDT or short in bear regimes
- Performance fee only charged on positive alpha above HODL baseline with high-water mark
- ZENT is a utility + governance token, NOT a security — no dividend distributions
- 50% of fees buy back and burn ZENT; 25% to GP engine; 15% to insurance; 10% to treasury
- Team vest > Investor vest (18% team, 12m cliff/36m; 15% investors, 6m cliff/24m)
- 45% of ZENT supply to community (50% at TGE, 50% linear over 24m)
- Smart contracts on Hyperliquid (HyperEVM), execution on HyperCore

---

## Requirements Trace

- R1. ZENT token: fixed 1B supply, ERC-20, no mint key, renounced ownership
- R2. Vault contracts: ERC-4626 compliant, zBTC/zETH/zSOL/zXRP, benchmark-denominated NAV
- R3. Performance fee: 20% only on positive alpha above HODL, with high-water mark
- R4. Fee split: 50% buyback+burn ZENT, 25% GP engine, 15% insurance, 10% treasury
- R5. Staking: ZENT stake required for vault access; bonding for strategy providers
- R6. Governance: ZENT holders vote on risk params, chain expansion, upgrades
- R7. GP Engine: off-chain genetic programming, trend-following strategies, on-chain trade logging
- R8. Execution: strategies execute on Hyperliquid HyperCore perps; vault reads order book without oracles
- R9. zkML roadmap: strategy verification via SP1/AggLayer (Phase 2 milestone)
- R10. Anti-rug: no mint key, programmatic vesting, LP lock, multi-audit, renounced ownership

---

## Scope Boundaries

### In Scope
- Full smart contract suite on HyperEVM (Solidity)
- GP Engine (off-chain Python/TypeScript)
- Frontend dashboard (Next.js)
- Deployment scripts and test suite

### Out of Scope for Phase 1
- zkML verification (Phase 2 milestone — "Roadmap to zkML" in whitepaper)
- Cross-chain vault deployment (Phase 2 Expansion milestone)
- Institutional / regulated wrapper (Phase 3 milestone)
- ZENT token listing on CEXs (handled separately)

### Deferred to Follow-Up Work
- zkML implementation: requires SP1 proof integration, deferred to Phase 2
- Multi-chain vault deployment: deferred until after zkML is live
- Frontend for governance proposals: deferred to Phase 2 (v1 shows vault dashboard only)

---

## Key Technical Decisions

- **Chain**: Hyperliquid (HyperEVM for smart contracts, HyperCore for execution)
  - Rationale: sub-second finality, shared-state between HyperEVM and HyperCore, no bridge attack surface, SP1/zkML already integrated
- **Language**: Solidity ^0.8 for smart contracts; TypeScript for GP engine and frontend
- **Framework**: Foundry for smart contract development and testing; Next.js 14 for frontend
- **Vault Standard**: ERC-4626 for vault shares; custom for benchmark-denominated NAV tracking
- **Token**: ZENT as ERC-20 with fixed supply, no mint, ownership renounced at launch
- **Fee Architecture**: Pull-based fee accrual; keeper-triggered distribution to buyback, GP engine, insurance, treasury
- **GP Engine**: Off-chain Python genetic programming; trade signals posted to chain via keeper; strategy hashes published to IPFS for verifiability
- **Architecture**: Monorepo with three packages: `contracts/`, `engine/`, `frontend/`

---

## Output Structure

```
zentory-protocol/
├── SPEC.md                          # Protocol specification (this file's sibling)
├── .github/
│   └── workflows/
│       └── ci.yml                  # GitHub Actions CI
├── contracts/                      # Solidity smart contracts (Foundry)
│   ├── src/
│   │   ├── ZENT.sol               # ERC-20 ZENT token
│   │   ├── vaults/
│   │   │   ├── BaseVault.sol     # ERC-4626 vault base contract
│   │   │   ├── zBTCVault.sol     # zBTC vault
│   │   │   ├── zETHVault.sol     # zETH vault
│   │   │   ├── zSOLVault.sol      # zSOL vault
│   │   │   └── zXRPVault.sol     # zXRP vault
│   │   ├── staking/
│   │   │   └── ZENTStaking.sol   # ZENT staking for vault access
│   │   ├── fees/
│   │   │   └── FeeDistributor.sol # Performance fee routing
│   │   ├── governance/
│   │   │   └── ZentGovernor.sol  # DAO governor (OpenZeppelin Governor)
│   │   ├── keeper/
│   │   │   └── StrategyExecutor.sol # Chain keeper for trade execution
│   │   └── interfaces/
│   │       ├── IVault.sol
│   │       ├── IZENT.sol
│   │       └── IFeeDistributor.sol
│   ├── test/
│   │   ├── ZENT.t.sol
│   │   ├── vaults/
│   │   │   └── BaseVault.t.sol
│   │   ├── staking/
│   │   │   └── ZENTStaking.t.sol
│   │   └── fees/
│   │       └── FeeDistributor.t.sol
│   ├── script/
│   │   └── Deploy.s.sol          # Deployment scripts
│   └── lib/
│       └── forge-std/
├── engine/                         # GP Engine (TypeScript / Python)
│   ├── src/
│   │   ├── genetic_programming/
│   │   │   ├── population.py     # GP population management
│   │   │   ├── fitness.py        # Fitness function (alpha vs HODL benchmark)
│   │   │   ├── crossover.py      # GP crossover operators
│   │   │   ├── mutation.py      # GP mutation operators
│   │   │   └── selection.py      # Tournament / roulette selection
│   │   ├── strategy/
│   │   │   ├── trend_follower.py # Trend-following strategy logic
│   │   │   ├── regime_detector.py # Bull/bear/cash regime detection
│   │   │   └── signal_generator.py # Generates trade signals
│   │   ├── execution/
│   │   │   └── hyperliquid_executor.py # Posts signals to chain
│   │   └── main.py               # GP evolution loop
│   ├── test/
│   │   ├── test_fitness.py
│   │   ├── test_regime_detector.py
│   │   └── test_signal_generator.py
│   └── requirements.txt
├── frontend/                       # Next.js frontend
│   ├── app/
│   │   ├── page.tsx             # Landing / vault overview
│   │   ├── vault/
│   │   │   └── [asset]/page.tsx  # Per-vault detail page
│   │   ├── stake/page.tsx       # ZENT staking interface
│   │   └── dashboard/page.tsx   # Performance dashboard
│   ├── components/
│   │   ├── VaultCard.tsx
│   │   ├── NAVChart.tsx
│   │   ├── ZENTStake.tsx
│   │   └── StrategyPerf.tsx
│   └── lib/
│       ├── wagmi.ts             # Web3 / wagmi config
│       └── supabase.ts          # Optional: off-chain data indexer
└── README.md
```

---

## Implementation Units

---

- [ ] U1. **Scaffold Monorepo and Project Infrastructure**

**Goal:** Create the project directory structure, initialize Foundry for contracts, Next.js for frontend, set up CI, linting, and tooling.

**Requirements:** R1 (infrastructure foundation)

**Dependencies:** None

**Files:**
- Create: `contracts/` (Foundry project)
- Create: `engine/` (Python project with requirements.txt)
- Create: `frontend/` (Next.js 14 app)
- Create: `SPEC.md` (protocol specification)
- Create: `.github/workflows/ci.yml`
- Create: `README.md`

**Approach:**
- Initialize Foundry in `contracts/` with `forge init --no-commit`
- Initialize Next.js in `frontend/` with TypeScript, Tailwind CSS
- Python environment for `engine/` with `pyproject.toml`
- Add OpenZeppelin contracts as `foundry remappings` (ERC-20, ERC-4626, Governor, Timelock)
- Set up GitHub Actions CI: run `forge build` + `forge test` on contracts; run pytest on engine

**Patterns to follow:** Standard Foundry + Next.js project conventions

**Test scenarios:**
- Happy path: CI pipeline runs successfully; all packages build without errors
- Edge case: Python package installs without conflicts on macOS/Linux/Windows

**Verification:** `forge build` succeeds; `npm run build` succeeds in frontend; `python -m pytest --collect-only` succeeds in engine

---

- [ ] U2. **ZENT ERC-20 Token Contract**

**Goal:** Deploy the ZENT ERC-20 token with fixed 1B supply, no mint function, ownership renounced.

**Requirements:** R1, R10

**Dependencies:** U1

**Files:**
- Create: `contracts/src/ZENT.sol`
- Create: `contracts/src/interfaces/IZENT.sol`
- Create: `contracts/test/ZENT.t.sol`

**Approach:**
- Use OpenZeppelin `ERC20Votes` for voting support
- Constructor mints totalSupply (1B with 18 decimals) to deployer
- Immediately on deploy: transfer remaining supply to allocation addresses per tokenomics table (community, team, investors, treasury, strategy incentives)
- Renounce ownership (`transferOwnership(address(0))`) and renounce admin roles at end of deployment script
- No `mint()` function — supply is fixed permanently
- Emit `Transfer` events for all initial allocations for traceability

**Patterns to follow:** OpenZeppelin ERC20Votes, OZ Hadhat pattern for deployment

**Test scenarios:**
- Happy path: ZENT totalSupply equals 1B * 10^18; deployer balance reflects allocation table
- Edge case: Any address can transfer ZENT; no address has minting rights
- Error path: Attempting to call `mint()` reverts
- Error path: Deploy script handles zero-address allocations gracefully

**Verification:** `forge test --match-contract ZENTTest -vv` passes; totalSupply() returns exactly 1_000_000_000 * 10^18; no `mint` selector in bytecode

---

- [ ] U3. **BaseVault ERC-4626 Contract**

**Goal:** Build the core ERC-4626 vault contract with benchmark-denominated NAV tracking, high-water mark performance fees, and immutable risk rails.

**Requirements:** R2, R3, R7, R10

**Dependencies:** U2

**Files:**
- Create: `contracts/src/vaults/BaseVault.sol`
- Create: `contracts/src/vaults/zBTCVault.sol` (copy with asset-specific params)
- Create: `contracts/src/vaults/zETHVault.sol`
- Create: `contracts/src/vaults/zSOLVault.sol`
- Create: `contracts/src/vaults/zXRPVault.sol`
- Create: `contracts/src/interfaces/IVault.sol`
- Create: `contracts/test/vaults/BaseVault.t.sol`

**Approach:**

The vault is the core product. Key design decisions:

1. **Benchmark tracking**: Store `lastNavPerShare` (NAV at last fee evaluation). At each rebalance, compute `currentNav = getNav()` and charge performance fee only on `(currentNav - lastNavPerShare) * shares` when positive.

2. **High-water mark**: Track `highWaterMark` per vault. If `currentNav < highWaterMark`, no fee and `highWaterMark` stays unchanged. When `currentNav > highWaterMark`, charge fee on the delta and update `highWaterMark`.

3. **ERC-4626 deposit/withdraw**: Use OZ `ERC4626` as base. Override `_deposit`, `_withdraw` for fee on profit only.

4. **Risk rails (immutable)**: Maximum leverage cap, maximum position size, circuit breaker drawdown threshold — all set as constants in the contract. Cannot be changed post-deployment without governance vote + timelock.

5. **NAV computation**: `getNav()` reads price from HyperCore precompile (no oracle needed — shared state). For Phase 1, use a trusted price feed adapter. NAV = current asset balance / totalShares.

6. **Fee recipient**: `FeeDistributor` contract receives accumulated fees and routes: 50% to ZENT buyback, 25% to GP engine keeper, 15% to insurance fund, 10% to treasury.

7. **Trade logging**: Each vault emits `TradeExecuted` events with timestamp, direction (long/short/cash), and size. Anyone can index these to verify strategy against NAV.

```solidity
// Vault core invariant
assert(getNav() >= highWaterMark || performanceFeeAccrued == 0);
```

**Patterns to follow:** OpenZeppelin ERC4626, Euler VaultKit, Morpho MetaMorpho vault patterns

**Test scenarios:**
- Happy path: First depositor gets 1:1 shares; second depositor gets proportionally fewer shares as yield accrues
- Happy path: Performance fee charged correctly only when NAV > highWaterMark
- Edge case: Deposit during negative NAV period — no fee charged, HWM unchanged
- Edge case: Large single deposit/withdrawal doesn't manipulate NAV
- Error path: Unauthorized keeper cannot trigger rebalance
- Error path: Circuit breaker triggers and blocks new deposits when drawdown > threshold

**Verification:** `forge test --match-contract BaseVaultTest -vv` passes; all invariant properties hold under property-based testing (use `forge/invariant`)

---

- [ ] U4. **ZENT Staking Contract**

**Goal:** ZENT holders stake to access vaults; staking is required for vault deposit. Also handles strategy provider bonding.

**Requirements:** R5, R10

**Dependencies:** U2, U3

**Files:**
- Create: `contracts/src/staking/ZENTStaking.sol`
- Create: `contracts/test/staking/ZENTStaking.t.sol`

**Approach:**
- Users call `stake(amount)` to lock ZENT for a duration. Locked ZENT earns veZENT (vote-escrowed) weight for governance.
- Vault access: vault contract checks `staking.balanceOf(user) >= minStake` before accepting deposit. This is checked via a simple `require` or precompile call — no cross-contract dependency on staking logic living inside the vault.
- Strategy bonding: model providers stake ZENT into a `ModelBonding` sub-contract. Slashing is implemented via a `slash(address provider, uint256 amount)` function callable only by the `RiskCouncil` governor.
- Slashing is all-or-nothing for severe underperformance (NAV < HODL for N consecutive epochs).

**Patterns to follow:** Curve VotingEscrow, Morpho staking patterns

**Test scenarios:**
- Happy path: User stakes 1000 ZENT; can then deposit into vault
- Happy path: Stake duration increases veZENT weight (linear lock time weighting)
- Edge case: User with insufficient ZENT stake cannot deposit into vault
- Edge case: Cannot withdraw staked ZENT before lock period ends
- Error path: Slashing correctly reduces provider's bonded ZENT
- Error path: Re-staking after lock expiry correctly resets weight

**Verification:** `forge test --match-contract ZENTStakingTest -vv` passes

---

- [ ] U5. **FeeDistributor Contract**

**Goal:** Accumulate vault performance fees and route them to the correct destinations: ZENT buyback, GP engine keeper, insurance fund, protocol treasury.

**Requirements:** R4, R10

**Dependencies:** U2, U3, U4

**Files:**
- Create: `contracts/src/fees/FeeDistributor.sol`
- Create: `contracts/src/interfaces/IFeeDistributor.sol`
- Create: `contracts/test/fees/FeeDistributor.t.sol`

**Approach:**
- `FeeDistributor` is the fee recipient for all vaults. Each vault calls `distributeFees(assets)` on this contract.
- The contract maintains a `FeeSchedule` struct: `buybackShare = 5000` (50%), `gpEngineShare = 2500` (25%), `insuranceShare = 1500` (15%), `treasuryShare = 1000` (10%).
- When called, the contract splits incoming assets according to the schedule:
  - `buybackPool`: uses assets to purchase ZENT from a DEX pool and send to burn address
  - `gpEnginePool`: assets held for keeper withdrawal
  - `insuranceFund`: assets held for vault drawdown claims
  - `treasury`: assets held for DAO-controlled spending
- Buyback is executed via a keeper or can be triggered permissionlessly (anyone can trigger, gas refunded from pool).

**Patterns to follow:** MetaMorpho fee router, Yearn fee management

**Test scenarios:**
- Happy path: Incoming fees correctly split into four pools per FeeSchedule
- Happy path: ZENT buyback executes via DEX and tokens are burned
- Edge case: Small fee amounts don't result in dust / rounding exploits
- Error path: Unauthorized caller cannot redirect fee flows

**Verification:** `forge test --match-contract FeeDistributorTest -vv` passes

---

- [ ] U6. **ZentGovernor DAO Contract**

**Goal:** On-chain governance for ZENT holders to vote on risk parameters, strategy approvals, and treasury spending.

**Requirements:** R6, R10

**Dependencies:** U2, U4

**Files:**
- Create: `contracts/src/governance/ZentGovernor.sol`
- Create: `contracts/src/governance/Timelock.sol`
- Create: `contracts/test/governance/ZentGovernor.t.sol`

**Approach:**
- Use OpenZeppelin `Governor` + `TimelockController` for a standard DAO setup
- Voting power: `ZENTStaking.veBalanceOf(voter)` — ZENT must be locked in staking to have voting weight
- Quorum: set at ~15% of circulating supply (adjustable)
- Timelock: 48-hour delay between proposal passing and execution
- Proposals can: adjust risk parameters (leverage caps, drawdown thresholds), whitelist new vault assets, transfer treasury funds, upgrade contracts via proxy pattern
- Contracts are behind a proxy (UUPS) so they can be upgraded via governance vote + timelock

**Patterns to follow:** OpenZeppelin Governor + TimelockController pattern; Compound Governor Bravo

**Test scenarios:**
- Happy path: Proposal can be created, voted on, queued, and executed via timelock
- Happy path: Voting power correctly reflects veZENT balance
- Edge case: Proposal with insufficient votes cannot be executed
- Edge case: Proposal cannot be executed before timelock delay expires
- Error path: Malicious proposal to drain treasury is blocked by timelock

**Verification:** `forge test --match-contract ZentGovernorTest -vv` passes

---

- [ ] U7. **Keeper / StrategyExecutor Contract**

**Goal:** Permissioned keeper that reads GP engine signals and executes trades on HyperCore via the vault's adapter contracts.

**Requirements:** R7, R8

**Dependencies:** U3, U5

**Files:**
- Create: `contracts/src/keeper/StrategyExecutor.sol`
- Create: `contracts/src/keeper/HyperCoreAdapter.sol`
- Create: `contracts/test/keeper/StrategyExecutor.t.sol`

**Approach:**
- `StrategyExecutor` is a keeper contract with a specific role (`KEEPER_ROLE`). Off-chain GP engine signs trade signals and submits them to this contract.
- The executor validates the signature, checks circuit breakers (leverage limits, position size limits), then calls `HyperCoreAdapter` to post the order to HyperCore.
- Adapter uses HyperCore precompiles to place perp orders atomically. The vault contract holds the margin.
- Each fill emits `TradeExecuted(asset, direction, size, entryPrice, timestamp)` — the public trade log.
- Trade signal format: `struct TradeSignal { address vault; int8 direction; // 1=long, -1=short, 0=close uint256 size; uint256 timestamp; bytes signature }`

**Patterns to follow:** Keeper patterns from Yearn, Gelato Network

**Test scenarios:**
- Happy path: Valid signed signal from GP engine executes a trade on HyperCore
- Edge case: Expired signal (>5 min old) is rejected
- Edge case: Signal exceeding leverage cap is truncated to cap
- Error path: Invalid signature reverts
- Error path: Circuit breaker triggers and blocks trade when vault drawdown exceeds threshold

**Verification:** `forge test --match-contract StrategyExecutorTest -vv` passes; integration test against Hyperliquid testnet (Holesky or mainnet fork)

---

- [ ] U8. **GP Engine (Off-Chain Genetic Programming)**

**Goal:** Implement the off-chain genetic programming engine that evolves trading strategies and generates trade signals.

**Requirements:** R7, R8

**Dependencies:** U7 (contract must exist for executor to connect)

**Files:**
- Create: `engine/src/genetic_programming/` (all GP modules)
- Create: `engine/src/strategy/` (trend follower, regime detector)
- Create: `engine/src/execution/hyperliquid_executor.py`
- Create: `engine/src/main.py`
- Create: `engine/test/` (unit tests)

**Approach:**

Core GP components:

1. **Population**: Fixed population of strategy chromosomes. Each chromosome encodes strategy rules (moving average crossovers, RSI thresholds, volatility filters, etc.) as a gene sequence.

2. **Fitness function**: `fitness = alpha_vs_benchmark - risk_penalty - fees - drawdown_penalty`
   - Alpha vs benchmark: `(strategy_return - HODL_return)` over the evaluation window
   - Risk penalty: penalize strategies with max drawdown > 20%
   - Fee penalty: estimated trading costs per rebalance
   - Out-of-sample test: fitness evaluated on a held-out window to prevent overfitting

3. **Selection**: Tournament selection — select 5 random chromosomes, breed the fittest two

4. **Crossover**: Two-point crossover on gene sequence; combine rule genes from parent strategies

5. **Mutation**: Randomly perturb 1-3 genes per chromosome with 10% probability per gene

6. **Regime detection**: Strategy chromosome includes regime detection genes (bull/bear/sideways). In bull regime, prefer long exposure. In bear, prefer cash or short.

7. **Signal generation**: Top-chromosome (elite strategy) generates trading signals at each epoch. Signals posted to `StrategyExecutor` via signed messages.

8. **IPFS publishing**: At end of each epoch, publish strategy parameter hash + fitness to IPFS (for on-chain verifiability).

**Execution loop** (runs every epoch, e.g., every 15 minutes):
```
1. Fetch latest market data (price, volume, order book)
2. Evaluate each chromosome on historical window → fitness
3. Select, crossover, mutate → new population
4. Test new population on out-of-sample window
5. Publish elite strategy hash to IPFS
6. Generate signal from elite strategy
7. Sign signal and submit to StrategyExecutor
8. Log performance metrics
```

**Patterns to follow:** DEAP (Distributed Evolutionary Algorithms in Python) library patterns; reusable `gp-framework`

**Test scenarios:**
- Happy path: GP loop runs one epoch and produces a valid trade signal
- Edge case: Population converges to a single strategy — diversity maintenance keeps multiple strategies
- Edge case: No clear signal (flat market) — output is "hold cash / no position"
- Error path: External data feed failure — GP loop logs error and skips epoch, does not halt

**Verification:** `python -m pytest` passes; manual backtest shows elite strategy outperforms HODL on historical data (BTC 2020-2025)

---

- [ ] U9. **Deploy Scripts and Mainnet Configuration**

**Goal:** Write Foundry deployment scripts to deploy all contracts to Hyperliquid mainnet (and testnet).

**Requirements:** R1-R10 (full deployment)

**Dependencies:** U1–U8 (all contracts must be written first)

**Files:**
- Create: `contracts/script/Deploy.s.sol`
- Create: `contracts/script/DeployTestnet.s.sol`
- Create: `contracts/broadcast/`

**Approach:**
- `Deploy.s.sol` deploys in order: ZENT → FeeDistributor → ZENTStaking → BaseVault (x4) → ZentGovernor → Timelock → StrategyExecutor
- After deployment, call `transferOwnership(timelock)` on all ownable contracts
- Renounce all admin roles; only timelock + governor can interact with privileged functions
- Generate deployment artifact (JSON) with all contract addresses for frontend use

**Patterns to follow:** OpenZeppelin Foundry Upgrades pattern for proxy deployment

**Test scenarios:**
- Happy path: Full deployment script runs on Holesky testnet without errors
- Happy path: All contract addresses are verified on Hyperliquid block explorer
- Error path: Deployment with insufficient gas reverts cleanly without leaving partial state
- Error path: Missing environment variables (deployer private key) fail with clear error message

**Verification:** Testnet deployment succeeds; `forge verify-contract` passes on all contracts; frontend can connect to all contract addresses

---

- [ ] U10. **Frontend Dashboard**

**Goal:** Build the Next.js frontend: vault overview, per-vault detail, NAV chart, ZENT staking interface, and performance dashboard.

**Requirements:** User-facing interface

**Dependencies:** U3, U4, U9 (contracts deployed and addresses known)

**Files:**
- Create: `frontend/app/page.tsx` (vault overview)
- Create: `frontend/app/vault/[asset]/page.tsx`
- Create: `frontend/app/stake/page.tsx`
- Create: `frontend/app/dashboard/page.tsx`
- Create: `frontend/components/` (all UI components)
- Create: `frontend/lib/wagmi.ts` ( wagmi / viem config)

**Approach:**
- Use wagmi + viem for smart contract reads/writes
- Read vault NAV per share from `totalAssets()` / `totalSupply()`
- Display benchmark-denominated performance: `V_model(t)` vs `V_HODL(t)` chart
- Staking interface: `useContractWrite` for `stake()`, `useContractRead` for balance + veZENT weight
- Dashboard: pull historical trade logs from `TradeExecuted` events; compute cumulative alpha
- Use shadcn/ui for components, Tailwind for styling

**Patterns to follow:** Next.js App Router, wagmi v2, shadcn/ui

**Test scenarios:**
- Happy path: User can connect wallet, stake ZENT, view vault performance
- Happy path: NAV chart renders correctly from on-chain data
- Edge case: Wallet disconnected — show connect button, disable stake UI
- Error path: Contract reverts — display clear error message to user

**Verification:** `npm run build` succeeds; `npm run dev` starts; manual smoke test on testnet

---

- [ ] U11. **Security Audit Preparation**

**Goal:** Prepare the contracts for professional security audits: full test suite, Slither analysis, documentation, and audit-ready code.

**Requirements:** R10 (anti-rug protections)

**Dependencies:** U2–U6, U9

**Files:**
- Modify: All contract files (add NatSpec comments, fix lint issues)
- Create: `contracts/audit-report.md` (pre-audit self-review)
- Run: Slither analysis, fix all findings

**Approach:**
- Add NatSpec comments to all public functions and events
- Run Slither (`slither .`) and fix all high/medium findings
- Run Medusa or Echidna for property-based invariant testing on vault contracts
- Write an `audit-report.md` documenting the security design, trust assumptions, and known limitations
- Ensure all access control is documented: who can call each privileged function
- Prepare a testnet deployment for auditors to interact with

**Patterns to follow:** OpenZeppelin audit preparation guide

**Test scenarios:**
- Slither reports no high/medium issues
- Invariant tests hold: vault cannot be drained, supply cannot be inflated, fees cannot be redirected

**Verification:** Slither exit code 0; all invariant properties pass under 10,000 random runs

---

- [ ] U12. **Mainnet Deployment**

**Goal:** Deploy all contracts to Hyperliquid mainnet, verify on block explorer, configure frontend for production.

**Requirements:** R1–R10

**Dependencies:** U11 (audit passed)

**Files:**
- Modify: `frontend/lib/constants.ts` (update contract addresses to mainnet)
- Create: `contracts/deployed-mainnet.json` (deployment artifact)

**Approach:**
- Execute `Deploy.s.sol` on mainnet with production parameters
- Verify all contracts on Hyperliquid block explorer
- Update frontend with mainnet contract addresses
- Deploy frontend to Vercel / Cloudflare Pages
- Configure DNS and domain
- Announce to community; begin Genesis phase (BTC model only, invite-only beta, $1M TVL cap)

**Verification:** All contracts verified on explorer; frontend loads vault data from mainnet; first deposits accepted

---

## System-Wide Impact

- **All vault operations depend on StrategyExecutor** — if the keeper is compromised, vault strategies cannot be updated. Mitigated: multisig keeper role, governor can revoke.
- **FeeDistributor is the central fee router** — all vault fees flow through it. A bug here affects all vaults. Mitigated: each vault can operate without FeeDistributor in emergency (circuit breaker).
- **GP Engine is off-chain** — if it fails, no new signals are generated. Vaults fall back to last known position. They do NOT automatically close positions.
- **HyperCore is centralized** — if Hyperliquid goes down, vault execution halts. This is an accepted L1 risk.

## Risks & Dependencies

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| VaultNAV oracle manipulation | Low | High | Use HyperCore precompile prices (no external oracle) |
| Keeper signature replay attack | Low | High | Include `nonce` and `block.timestamp` in signal; reject stale signals |
| GP engine produces negative alpha | Medium | Medium | Performance fee only charged on positive alpha; vault depositors protected |
| ZENT token classified as security | Medium | High | No dividend distributions; buyback+burn only; legal opinion before launch |
| Team vesting wallet compromise | Low | High | Multisig vesting contract; timelock on all team claims |
| Smart contract upgrade key compromise | Low | High | Proxy pattern with governor + timelock; no single admin key |

## Dependencies / Prerequisites

1. Hyperliquid HyperEVM testnet (Holesky-equivalent) must be accessible
2. Hyperliquid RPC endpoints and chain ID
3. IPFS node access for strategy hash publishing
4. At least 2 independent security auditors for U11
5. Deployer wallet with sufficient HYPE for gas + initial liquidity

## Documentation Plan

- `SPEC.md` — protocol specification (this plan)
- `contracts/README.md` — contract architecture, deployment guide
- `engine/README.md` — GP engine setup, running locally
- `frontend/README.md` — frontend setup, env vars
- `docs/audits/` — audit reports (after U11)

## Operational / Rollout Notes

- **Genesis phase (Months 1-3)**: BTC model only, invite-only beta, $1M TVL cap. Deploy BTC vault only. No token. Track performance on-chain from day one.
- **Validation phase (Months 4-6)**: Add ETH model, public beta. Still no token. Establish 6-month verified track record.
- **Token Launch (Months 7-9)**: ZENT token generation event, staking activation, fee buyback/burn live. CEX listing discussions begin.
- **Expansion (Months 10-18)**: SOL + XRP vaults, cross-chain deployment (after zkML).

---

## Sources & References

- Origin document: [whitepaper/page.tsx](whitepaper/page.tsx)
- ERC-4626 specification: https://eips.ethereum.org/EIPS/eip-4626
- OpenZeppelin Contracts: https://github.com/OpenZeppelin/openzeppelin-contracts
- Hyperliquid developer docs: https://hyperliquid.gitbook.io/hyperliquid-docs
- Foundry framework: https://book.getfoundry.sh/
- Genetic Programming literature: Koza, John R. "Genetic Programming" (standard GP reference)
- Solana Vault Standard (for comparison): https://github.com/solanabr/solana-vault-standard
