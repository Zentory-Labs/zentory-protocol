# Hybrid execution + venue fills → Supabase metrics — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire up a **hybrid** loop for HyperEVM testnet: **on-chain `StrategyExecutor` submissions** + **Hyperliquid testnet `userFills` truth**, persisted in Supabase for dashboards — while polishing the homepage swap UX (real balances) and vault NAV precision.

**Architecture:** Keep **venue fills** canonical for trade/PnL stats, **chain txs** canonical for auditability. A small Python poll loop calls `POST https://api.hyperliquid-testnet.xyz/info` with `{"type":"userFills","user":...}` per vault trading wallet, upserts rows into Postgres, and optional linkage to on-chain attempts by `oid` / time-window heuristics. Frontend reads remain **viem + `/api/rpc`** for reliability.

**Tech stack:** Next.js + viem/wagmi, Supabase Postgres, Python 3.11 + httpx (already in engine), Hyperliquid Info API (`/info`).

---

## File map

- **Frontend**
  - `frontend/components/SwapWidget.tsx` — replace hard-coded balances with real reads; fix hydration locale mismatch for preset labels.
  - `frontend/app/page.tsx` — fix `fmt`/`fmtUsd` bigint math (use `formatUnits`) so tiny NAV doesn’t stringify to `0`.
  - `frontend/lib/format-balance.ts` (new) — small pure helpers (tested via `node` one-liner in CI task or local run).
- **Supabase**
  - `supabase/migrations/2026_04_27_005_hybrid_execution_tables.sql` — tables: `vault_trading_accounts`, `execution_attempts`, `hl_user_fills`, `fill_match_log`.
- **Engine**
  - `engine/src/venue/hyperliquid_info.py` — minimal typed client for `userFills` / `userFillsByTime`.
  - `engine/scripts/poll_hyperliquid_fills.py` — CLI poll loop → upserts into Supabase via REST (`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`).

---

### Task 1: Fix vault NAV formatting precision on homepage

**Files:**
- Modify: `frontend/app/page.tsx`

- [ ] **Step 1: Replace integer bigint truncation formatting**

```tsx
import { formatUnits } from "viem";

function fmtUnits(value: bigint, decimals: number, fractionDigits: number): string {
  const s = formatUnits(value, decimals);
  const n = Number(s);
  if (!Number.isFinite(n)) return "—";
  return n.toLocaleString("en-US", {
    minimumFractionDigits: 0,
    maximumFractionDigits: fractionDigits,
  });
}
```

Use `fmtUnits` for both `fmt` and `fmtUsd` (instead of `(value / 10**decimals)` integer division).

- [ ] **Step 2: Typecheck**

Run: `cd frontend && npx tsc --noEmit`  
Expected: exit 0

- [ ] **Step 3: Smoke E2E**

Run: `cd frontend && npm run test:e2e`  
Expected: PASS

---

### Task 2: SwapWidget shows real balances (or honest “Connect wallet” / “Not on HyperEVM” states)

**Files:**
- Modify: `frontend/components/SwapWidget.tsx`
- Create: `frontend/lib/format-balance.ts`

- [ ] **Step 1: Add formatting helper**

Create `frontend/lib/format-balance.ts`:

```ts
export function formatTokenAmountDisplay(value: bigint | undefined, decimals: number, maxFrac = 6): string {
  if (value === undefined) return "—";
  if (value === 0n) return "0";
  const base = 10n ** BigInt(decimals);
  const whole = value / base;
  const frac = value % base;
  if (whole > 0n) {
    return `${whole.toLocaleString("en-US")}.${frac
      .toString()
      .padStart(decimals, "0")
      .replace(/0+$/, "")
      .slice(0, maxFrac)}`.replace(/\.$/, "");
  }
  const s = frac.toString().padStart(decimals, "0").replace(/^0+/, "");
  const trimmed = s.slice(0, maxFrac).replace(/0+$/, "");
  return trimmed.length ? `0.${trimmed}` : "0";
}
```

- [ ] **Step 2: Wire wagmi reads**

In `SwapWidget.tsx`:

```tsx
import { useAccount, useBalance, useReadContracts } from "wagmi";
import { parseAbi } from "viem";
import { addresses, HYPEREVM_TESTNET } from "@/lib/contracts";

const erc20Abi = parseAbi([
  "function balanceOf(address) view returns (uint256)",
  "function decimals() view returns (uint8)",
]);

const ASSET: Record<"ETH"|"BTC"|"USDT"|"SOL", `0x${string}` | null> = {
  ETH: addresses.WETH,
  BTC: addresses.WBTC,
  SOL: addresses.WSOL,
  USDT: null,
};

function useWalletTokenBalance(symbol: "ZENT"|"ETH"|"BTC"|"USDT"|"SOL") {
  const { address, isConnected, chainId } = useAccount();
  const onChain = isConnected && chainId === HYPEREVM_TESTNET.id;

  const native = useBalance({ address, chainId: HYPEREVM_TESTNET.id, query: { enabled: onChain && symbol === "ETH" } });

  const tokenAddress = symbol === "ZENT" ? addresses.ZENT : ASSET[symbol];
  const token = useReadContracts({
    contracts: onChain && tokenAddress
      ? [
          { chainId: HYPEREVM_TESTNET.id, address: tokenAddress, abi: erc20Abi, functionName: "decimals" },
          { chainId: HYPEREVM_TESTNET.id, address: tokenAddress, abi: erc20Abi, functionName: "balanceOf", args: [address!] },
        ]
      : [],
    query: { enabled: onChain && !!tokenAddress && symbol !== "ETH" },
  });

  // return { label, valueText } handling USDT unsupported (null) and wrong chain
}
```

Rendering rules:
- Not connected → `Balance: —` on both sides (or “Connect wallet” smaller label)
- Connected but wrong chain → `Balance: wrong network`
- ETH → native HYPE balance via `useBalance`
- Others → ERC20 balances
- USDT missing address → `Balance: n/a (testnet)`

- [ ] **Step 3: Fix preset label hydration**

Replace `amt.toLocaleString()` with:

```tsx
new Intl.NumberFormat("en-US", { maximumFractionDigits: 0 }).format(amt)
```

- [ ] **Step 4: Remove scroll-to-top onBlur** (bad mobile UX)

Delete `handleBlur` and `onBlur={handleBlur}` on input.

- [ ] **Step 5: Verify**

Run: `cd frontend && npx tsc --noEmit && npm run test:e2e`

---

### Task 3: Supabase schema for hybrid pipeline

**Files:**
- Create: `supabase/migrations/2026_04_27_005_hybrid_execution_tables.sql`

- [ ] **Step 1: Create tables (idempotent-ish)**

```sql
create extension if not exists pgcrypto;

create table if not exists public.vault_trading_accounts (
  vault_address text primary key,
  hl_user_address text not null,
  asset text not null,
  notes text,
  created_at timestamptz not null default now()
);

create table if not exists public.execution_attempts (
  id uuid primary key default gen_random_uuid(),
  vault_address text not null,
  tx_hash text not null,
  chain_id int not null default 998,
  nonce numeric,
  direction smallint,
  size_raw text,
  price_raw text,
  expiry_ts bigint,
  status text not null default 'submitted',
  error text,
  created_at timestamptz not null default now(),
  unique (vault_address, tx_hash)
);

create table if not exists public.hl_user_fills (
  id bigserial primary key,
  vault_address text not null references public.vault_trading_accounts(vault_address) on delete cascade,
  hl_user_address text not null,
  source text not null default 'hyperliquid_testnet_info',
  fill_key text not null,
  coin text,
  px text,
  sz text,
  side text,
  dir text,
  fee text,
  fee_token text,
  closed_pnl text,
  oid text,
  tid text,
  time_ms bigint,
  hash text,
  raw jsonb not null,
  inserted_at timestamptz not null default now(),
  unique (vault_address, fill_key)
);

create index if not exists hl_user_fills_time_idx on public.hl_user_fills (vault_address, time_ms desc);
```

`fill_key` should be computed in the ingester as:

`f"{tid}:{hash}:{time_ms}"` (fallback `hash:time_ms` if tid missing).

- [ ] **Step 2: RLS**

For this phase, **service-role only** ingestion; add read policies for anon if you already expose dashboards via Supabase client keys (match your existing `signals` policies pattern).

---

### Task 4: Hyperliquid testnet fills poller → Supabase upsert

**Files:**
- Create: `engine/src/venue/hyperliquid_info.py`
- Create: `engine/scripts/poll_hyperliquid_fills.py`

- [ ] **Step 1: Minimal Info client**

```python
import httpx

class HyperliquidInfoClient:
    def __init__(self, base_url: str = "https://api.hyperliquid-testnet.xyz/info", timeout: float = 30.0):
        self._c = httpx.Client(base_url=base_url, timeout=timeout)

    def user_fills(self, user: str):
        r = self._c.post("", json={"type": "userFills", "user": user})
        r.raise_for_status()
        return r.json()
```

- [ ] **Step 2: Poll + upsert**

CLI env vars:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `VAULT_TRADING_MAP` as JSON: `{ "0xVault...": "0xHlUser..." }`

For each vault:
- fetch fills
- compute `fill_key`
- `POST /rest/v1/hl_user_fills?on_conflict=vault_address,fill_key`

Use PostgREST upsert headers:

```
Prefer: resolution=merge-duplicates
```

Payload rows include `raw` json.

- [ ] **Step 3: Dry run test (local)**

Run:

```bash
cd engine
python scripts/poll_hyperliquid_fills.py --once
```

Expected logs: counts per vault + HTTP 200/201 from Supabase.

---

### Task 5: “Close the loop” manually (owner-operated secrets)

You (project owner) must provide / configure:

- `vault_trading_accounts` rows (4 wallets)
- `SUPABASE_SERVICE_ROLE_KEY` in a secure runner (local or GitHub Actions)
- funded keeper key is already assumed for `executeSignal` txs

---

## Self-review (spec coverage)

- **Hybrid C** covered: chain attempts table + venue fills table + mapping table.
- **Per-vault accounts** covered: `vault_trading_accounts`.
- **Gaps:** automatic linkage table `execution_attempts ↔ hl_user_fills` is deferred to a follow-up once we confirm matching keys (`oid` mapping rules) from your live testnet behavior.

---

**Plan complete.** Two execution options:

1. **Subagent-driven** (fresh subagent per task)
2. **Inline execution** (this session / batch with checkpoints)

Reply with **1** or **2**.
