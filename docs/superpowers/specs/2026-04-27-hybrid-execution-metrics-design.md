# Hybrid execution + investor metrics — design (HyperEVM testnet → prod)

## Goal

Deliver a **testnet-realistic trading + accounting loop** that investors can inspect:

- **On-chain**: immutable audit trail (`StrategyExecutor.executeSignal` tx hashes, nonces).
- **Venue**: **Hyperliquid fills** per vault trading account as the canonical **PnL/trade truth**.
- **Product UX**: dashboards that reconcile **signals → txs → fills → NAV/TVL/fees**.

## Constraints & principles

- **Do not pretend mock UI balances are chain balances** — swap balances must reflect wallet token balances where possible.
- **One trading account per vault** (already chosen): clean attribution for metrics and reporting.
- **Migrate cleanly to production**: keep interfaces stable (tables + row shapes), swap RPC URLs + keys only.

## Components

### 1) Vault trading accounts (Hyperliquid)

Create/maintain **four Hyperliquid trading accounts**, one mapped to each vault (`zBTC`, `zETH`, `zSOL`, `zXRP`).

Store mapping in Supabase `vault_trading_accounts`:

- `vault_address` (text, PK)
- `asset` (text)
- `hl_user` / `hl_address` (fields depend on Hyperliquid account model)
- `created_at`

### 2) On-chain submission path (already deployed)

Flow:

1. Engine produces signed signal payload (existing `engine` signer utilities).
2. Keeper submits `StrategyExecutor.executeSignal(...)` on HyperEVM testnet.
3. Contract routes to `HyperCoreAdapter.sendLimitOrder(...)` as applicable.

Persist “attempt” rows in Supabase `execution_attempts`:

- `id` uuid PK
- `vault_address`
- `nonce`
- `tx_hash`
- `submitted_at`
- `direction`, `size`, `price`, `expiry`
- `status` (`submitted`, `reverted`, `confirmed`)

Indexer source: RPC logs / receipts (reuse patterns in `engine/src/monitor/event_monitor.py`).

### 3) Venue fill ingestion (canonical trades)

Worker process (new module under `engine/src/monitor/` or `engine/src/execution/`) connects to Hyperliquid API/WS **per vault account** and writes `fills`:

- `fill_id` (venue id; unique)
- `vault_address`
- `account` (hl account identifier)
- `timestamp`
- `side`, `size`, `price`, `fees`, `asset`
- raw JSON payload for audit

Linkage strategy (hybrid):

- Primary: match by **nonce / client order id** if exposed by venue API.
- Fallback: match by time window + size/price tolerance + vault account.
- Always retain both sides (attempt + fill) even if linkage is imperfect; expose `match_confidence`.

### 4) Accounting + metrics rollups

Materialized daily rollups per vault:

- realized/unrealized PnL (venue truth)
- gross/net of fees
- win-rate and distribution stats (from fills)
- TVL/NAV reconciliation vs on-chain vault reads (`totalAssets`, `getNavPerShare`)

Protocol-level aggregates for `/dashboard`.

### 5) Investor-facing surfaces

- `/dashboard`: protocol + vault performance (venue-backed where available; clearly label “venue-confirmed”).
- `/signals`: tie signal rows to `execution_attempts.tx_hash` when present.
- Optional: public “Proof” page listing latest txs + linked fills.

## Security & ops

- Secrets live only in deployment environments (Vercel/Supabase/CI secrets), never committed.
- Separate keys: **keeper**, **signer**, **venue API** (read-only if possible).

## Open inputs required from project owner

1. **Hyperliquid API credentials** for each vault trading account (or a single API key with multi-account access if supported).
2. **Keeper private key** funded on HyperEVM testnet for gas.
3. **Signer private key** configured as `authorizedSigner` on `StrategyExecutor` (must match contract config).
4. Confirmation of **fee recipient + operational wallets** for demo reporting.

## Success criteria (testnet demo)

- At least **one end-to-end example per vault**: signal → confirmed tx → ≥1 venue fill → appears in Supabase → visible on dashboard charts.
- Dashboard labels distinguish **venue-confirmed** vs **on-chain-only** metrics.
