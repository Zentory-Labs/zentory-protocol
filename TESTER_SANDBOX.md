# ZENTORY Tester Sandbox — making the testnet usable

Concrete checklist + onboarding script for an investor/early-tester sandbox on
HyperEVM testnet. Companion to `ROADMAP.md` (Phase 1) and pairs with the
already-built shadow stack — no more contract work needed, just operational
setup and a guided run-through.

What testers should walk away seeing:
- Deposited testnet WBTC into a vault.
- The deployed (turnover-controlled) signal flipping LONG ↔ FLAT autonomously
  every 4H, signed and logged on-chain forever.
- Their vault NAV moving with strategy PnL — proven by the **HOLD / GHOST /
  ACTUAL** tile on the vault page.
- Redeem and receive their share of the underlying.

This is the analysis's checklist (A) made concrete, mapped to artifacts that
exist today.

---

## Part A — Operator setup (you, before testers arrive)

Run once. Verify each step before moving on.

### A1. Infra hardening (audit F-02 / multisig blockers)
- [ ] Move secrets off OneDrive auto-sync; store in a managed secrets vault.
- [ ] Rotate the leaked deployer EOA's keys; migrate `DEFAULT_ADMIN_ROLE`
      to a multisig (`StrategyExecutor`, vaults, `SignalRegistry`,
      `EpochScoring`).
- [ ] Paid RPC for the keeper + indexer.
- [ ] Real (paid) Supabase, not free tier (it has been deleted once already).
- [ ] Monitoring: at minimum, an alert if `currentEpochId` doesn't advance
      within 5h or the keeper wallet's nonce stalls > 1 epoch.

### A2. Deploy the shadow stack (one-click)
```powershell
cd zentory-protocol/contracts
$env:UNDERLYING = "0x08890A5B7D6D157Da65C04C19150fF7d124eaE40"  # testnet WBTC mock
.\deploy-shadow-stack.ps1
```
Captures three addresses: `sUSDC`, `ORACLE`, `SWAP_ADAPTER`.

### A3. Deploy the SpotVault
```powershell
$env:UNDERLYING   = "0x08890A5B..."
$env:CASH         = "<sUSDC from A2>"
$env:ORACLE       = "<ORACLE from A2>"
$env:SWAP_ADAPTER = "<SWAP_ADAPTER from A2>"
.\deploy-spot-vault.ps1
```
Captures `SPOT_VAULT`.

### A4. Wire roles + fund reserves (one cast script)
- Grant `VAULT_ROLE` on `SWAP_ADAPTER` to `SPOT_VAULT`.
- Mint sUSDC + testnet WBTC reserves to `SWAP_ADAPTER` (e.g. 100k sUSDC,
  100 WBTC equivalent — enough to handle expected rebalance flows).
- Verify with one read: `SWAP_ADAPTER.balanceOf(sUSDC)` and
  `SWAP_ADAPTER.balanceOf(WBTC)` are non-zero.

### A5. Keeper config
Existing Railway keeper service. Add **two** responsibilities to its 4H loop:
1. `ORACLE.setPrice(currentBtcUsd_8dec)` — pull live BTC/USD from Binance,
   push to the testnet oracle so SpotVault's staleness guard stays satisfied.
2. `SPOT_VAULT.rebalanceTo(targetBps)` — read the deployed (hysteresis)
   signal from the forward recorder ledger / engine and call rebalance.

Both functions are gated by roles already granted in A2/A3. No keys typed.

### A6. dApp update
- Add the new vault address (`SPOT_VAULT`) to `zentory-app/lib/contracts.ts`
  (alongside the existing zBTC/etc.). Label it "zBTCs — Shadow Testnet" so it
  is unmistakably the demo vault.
- Surface the **HOLD / GHOST / ACTUAL** tile on the vault page. The engine's
  `strategy/ghost_portfolio.py` computes it; the dApp consumes
  `getNavPerShare()` for ACTUAL, the indexed signal stream for GHOST, and the
  vault's deposit-time price × starting units for HOLD.
- Surface a **"Live signal" widget**: deployed target (LONG/FLAT), current
  ensemble raw value, time since last rebalance. Reads from the forward
  recorder ledger via the indexer.

### A7. Observability checks (before testers)
- [ ] One full 4H cycle: oracle updates, signal logs, rebalance fires (or
      correctly no-ops via the deadband), `getNavPerShare()` reads cleanly.
- [ ] Forward recorder ledger has at least 14 days of entries; verify chain
      is intact (`forward_recorder.py --verify`).
- [ ] Ghost Portfolio CLI demo on the recorder ledger produces a sane plot.

---

## Part B — Tester onboarding (5-step script)

This is what a tester literally does, end-to-end, in ≤ 20 minutes.

### B1. Get a testnet wallet + HYPE
- Install Rabby/MetaMask, add HyperEVM testnet (chain id `998`, RPC
  `https://rpc.hyperliquid-testnet.xyz/evm`).
- Receive testnet HYPE from the faucet (one click on
  `app.zentorylabs.com/faucet`).

### B2. Get testnet WBTC
- One click on the dApp's vault page: "Get 1 testnet WBTC" → mints from the
  mock to the tester's wallet.

### B3. Deposit into the vault
- "Deposit 1 WBTC into zBTCs." Two transactions (approve + deposit) signed in
  Rabby. The vault shows the tester's share balance and current NAV.

### B4. Watch the loop
- Below the position, three live readouts:
  - **Live signal**: LONG / FLAT (deployed target). Updates every 4H epoch.
  - **HOLD / GHOST / ACTUAL** tile, in BTC terms. ACTUAL tracks the vault's
    `getNavPerShare()`; GHOST tracks the signal-stamped attribution; HOLD is
    the constant baseline (1.0 BTC/share).
  - **Signal history**: every signed signal in `SignalRegistry`, linked to
    the block. Shows the immutability claim is real.
- Leave the tab open. Refresh after 4–24h. The numbers move.

### B5. Redeem
- "Redeem all shares." The vault swaps cash → underlying if needed and pays
  out WBTC. Display the depositor's final WBTC vs. what HOLD would have been
  over the same window. **This is the moment of truth: depositors see the
  strategy's value or absence of value, in the underlying.**

---

## Part C — Honest limitations testers should know up front

Tell them, on the page, in plain English:
- This is **testnet**. Tokens are mocks. No real money.
- The swap venue is a **shadow adapter** — fills at oracle price with simulated
  slippage. The production version will route to Hyperliquid spot.
- The price oracle is **keeper-pushed**, not Chainlink. Fail-closed staleness
  guards still apply (vault reverts NAV reads on stale feed).
- The strategy is **long/flat spot only**. It does not short. It is *NOT*
  guaranteed to beat HOLD in every window — it is designed to roughly halve
  drawdowns and accumulate underlying across full cycles.
- The Ghost Portfolio CLI/engine is the canonical attribution. The dApp tile
  is a presentation layer over the same numbers.

---

## Part D — What metrics to publish from the testnet run

For the Phase-1 GO-GATE evidence:
- Continuous operation streak (days without keeper/oracle outage > 1h).
- Cumulative signal alpha (GHOST − HOLD), in the underlying, since deploy.
- Cumulative execution drag (ACTUAL − GHOST).
- Max drawdown of ACTUAL vs. HOLD over the window.
- Number of signed signals on-chain (immutability proof).
- Number of testers who completed B1–B5.

Publish these as a live dashboard on the marketing site or a status page.
They become the evidence package for the audit, the legal opinion, and the
eventual Phase 2 cohort recruitment.
