# Spec: Make Vault NAV Reflect Strategy PnL (Option A — spot, in-vault)

Status: proposal · Owner: Edge · Complements `zentory-engine/SPOT_EXECUTION_SPEC.md`
(signal generation/posting). This spec is the **on-chain half**: the gearbox that
turns a signal into a NAV-moving trade so a depositor actually benefits.

## 1. The gap (verified in `contracts/src/vaults/BaseVault.sol`)

```solidity
function totalAssets() public view returns (uint256) {
    return IERC20(asset()).balanceOf(address(this)) - performanceFeeAccrued;
}
```

A vault's NAV = the spot tokens it holds. `recordTrade()` only writes bookkeeping
(`currentDirection`, `currentPositionSize`, `tradeHistory`) — it moves **no tokens**,
so it does **not** change `totalAssets()` or share value. `closePosition()` just
zeroes those fields. `StrategyExecutor.executeSignal → HyperCoreAdapter.sendLimitOrder`
fires a **perp** order whose margin the vault never posts and whose PnL never
returns to the vault. **Net: depositor shares are decoupled from strategy PnL.**
Closing this is the difference between "infra demo" and "stake and earn."

## 2. Design (Option A): vault denominated in the underlying, holds asset-or-cash

The vault stays **denominated in its underlying** (zBTC vault accounts in WBTC) —
this preserves the "depositors earn yield in the underlying, not USD" design that
keeps the securities posture clean. The strategy is long/flat **spot**:

- **LONG**  → vault holds the underlying (WBTC).
- **FLAT**  → vault holds cash (USDC).

NAV is measured **in underlying units**. The edge shows up as **more WBTC per share**:
when the strategy sits in USDC through a drawdown and the price falls, the same USDC
buys back **more WBTC** → NAV-in-WBTC per share rises → it beats passive HOLD. This is
exactly the validated long/flat spot strategy, and it pays **no funding** (vs the
current perp path, which the funding analysis showed ~halves returns).

### Accounting model
```
totalAssets()  (in underlying units) =
      assetBalance
    + cashToAsset(cashBalance)           // USDC valued in WBTC via oracle
    - performanceFeeAccrued
cashToAsset(usdc) = usdc * 1e{assetDec} / price_asset_per_usdc   // Chainlink
```
- HOLD baseline (per share, in WBTC) = constant (passive holder keeps fixed WBTC).
- A strategy that ends a cycle with **more WBTC/share than it started** has real alpha.
- High-water-mark fee (`evaluateFees`) already keys off `getNavPerShare()` — once
  `totalAssets()` reflects both legs, the 15%/20% perf fee works unchanged.

## 3. Contract changes

### 3a. New vault (`SpotVault` / BaseVault v2) — NOT an edit
`BaseVault` is constructor-based and **non-upgradeable** (immutable rails). So this
ships as a **new vault contract** per asset (zBTCVault v2 …) with a **depositor
migration**, not an in-place change. Re-opens the audit gate.

New/changed members:
- `IERC20 public immutable cashAsset;`          // USDC
- `AggregatorV3Interface public immutable priceFeed;` // asset/USD (Chainlink; reuse EpochScoring feed)
- `address public spotAdapter;`                 // executes the swaps
- `uint16 public targetWeightBps;`              // 0..10000, set by keeper from signal
- **`totalAssets()`** → asset + oracle-valued cash − fees (formula above), with
  oracle **staleness + deviation** guards (revert/freeze NAV if feed stale).
- **`rebalanceTo(uint16 targetWeightBps)`** (KEEPER_ROLE, replaces cosmetic
  `recordTrade`): compute desired asset vs cash split of `totalAssets()`, compute the
  delta, call `spotAdapter` to swap the delta (WBTC↔USDC). Respect `rebalanceThresholdBPS`
  (already a constructor param) to suppress dust churn — directly addresses the 970-trade
  churn seen in the fractional paper run.
- **Withdraw/redeem**: ERC-4626 pays in `asset()` (WBTC). If the vault is in cash,
  either (i) swap the required USDC→WBTC on withdraw, or (ii) keep a WBTC buffer, or
  (iii) pay pro-rata in-kind (breaks pure ERC-4626). **Decision needed** — recommend
  (i) with slippage bound, falling back to (iii) under circuit-breaker.
- Keep: circuit breaker, inflation-offset (`_decimalsOffset()=6`), fee logic.

### 3b. New `SpotExecutionAdapter` (replaces the perp `HyperCoreAdapter` for these vaults)
- `swap(assetIn, assetOut, amountIn, minOut)` → executes a **spot** trade on
  Hyperliquid spot (CoreWriter spot-order action) or a HyperEVM DEX router.
- No leverage, no funding, no `reduceOnly`.
- **Custody/async note:** CoreWriter is fire-and-forget (fills next block), so swaps
  are **not atomic** with the EVM call. The vault must track an "in-flight" state and
  reconcile actual balances post-fill before recomputing NAV (don't double-count an
  order that hasn't filled). Simplest: settle-then-account, or an on-HyperEVM atomic
  DEX if one with enough liquidity exists.

### 3c. `StrategyExecutor`
- Add `executeRebalance(vault, targetWeightBps, nonce, expiry, signature)` that
  verifies the signed signal (same EIP-712 scheme) and calls `vault.rebalanceTo(...)`,
  instead of `hyperCore.sendLimitOrder`. The signal's **target weight** (see engine
  spec Option A/B) is the payload.

## 4. Hard constraints / risks

- **New vaults + migration** (BaseVault immutable). Plan a migration: pause old vault,
  let depositors withdraw → deposit into v2, or a scripted migration. Significant.
- **Re-audit** — new vault + adapter + oracle-based NAV is a fresh audit surface.
- **Oracle = NAV attack surface.** NAV now depends on a price feed; needs robust
  Chainlink feeds, staleness checks, deviation bounds, possibly TWAP. A bad/manipulated
  feed mis-prices shares (deposit/withdraw arb). This is the #1 new risk.
- **Async fills** (CoreWriter) → in-flight accounting; avoid NAV flicker / sandwich on
  rebalance.
- **Spot liquidity** on Hyperliquid for SOL/XRP pairs; slippage caps on swaps.
- **Deposits arrive in WBTC** and shift actual weight; keeper re-aligns on next signal
  or when drift > `rebalanceThresholdBPS`.

## 5. Ghost Portfolio (#69) in this model
- **HOLD** = passive: starting WBTC/share held flat (price-independent in WBTC terms).
- **GHOST** = compounded if every signal executed at its stamped price (no slippage).
- **ACTUAL** = `getNavPerShare()` (real, post-swap, post-fee).
- ACTUAL − HOLD = total alpha; GHOST − HOLD = signal alpha; ACTUAL − GHOST = execution
  drag (slippage/fees). Index from `TradeSignalExecuted` + vault NAV snapshots + fills.

## 6. Rollout (testnet first, one vault)
1. Build `SpotVault` + `SpotExecutionAdapter`; unit + integration tests (deposit →
   signal → rebalance → price move → assert NAV/share changed; withdraw honoured).
2. Deploy **zBTC v2** on testnet alongside the live signal loop.
3. **Shadow mode first:** run rebalances with a tiny seed; verify NAV tracks the
   research/paper curve (reuse `zentory_algo` as the oracle of truth).
4. Build Ghost Portfolio on zBTC v2; surface HOLD/GHOST/ACTUAL + signal history in dApp.
5. Only then: ETH/SOL v2. **XRP is protection-only — defer.**
6. Mainnet + audit + security fixes (leaked deployer key, secrets) before real capital.

## 7. Open decisions for Edge
- Withdraw handling when in cash: swap-on-withdraw (i) vs in-kind (iii)?
- Execution venue: Hyperliquid spot via CoreWriter vs a HyperEVM DEX router?
- Cash asset: USDC (assume) — confirm the canonical testnet/mainnet USDC.
- Migration mechanics for existing zBTC depositors (withdraw-redeposit vs scripted).

## 8. Checklist
- [ ] Pick withdraw model + execution venue + cash asset (§7).
- [ ] `SpotExecutionAdapter` (spot swap + async-fill reconcile).
- [ ] `SpotVault` (totalAssets w/ oracle, rebalanceTo, withdraw path, oracle guards).
- [ ] `StrategyExecutor.executeRebalance` (target-weight signal → vault.rebalanceTo).
- [ ] Tests: NAV moves with PnL; beats HOLD in-WBTC across a sim cycle; withdraw safe.
- [ ] Deploy zBTC v2 testnet; shadow-run vs `zentory_algo` curve.
- [ ] Ghost Portfolio (#69) + dApp surfacing.
- [ ] Migration plan; then audit + mainnet.
