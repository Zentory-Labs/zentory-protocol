-- ============================================================
-- Zentory Protocol — Vault NAV History + Performance Metrics
-- Stores hourly NAV snapshots per vault for chart display
-- Run this in: Supabase Dashboard → SQL Editor
-- ============================================================

-- ─── Vault NAV History ─────────────────────────────────────
-- Hourly snapshots of NAV per share and total assets per vault
drop table if exists public.vault_nav_history;

create table public.vault_nav_history (
  id            text        primary key default uuid_generate_v4(),
  vault_symbol  text        not null,   -- 'zETH' | 'zBTC' | 'zXRP' | 'zSOL'
  snapshot_at   timestamptz not null,
  nav_per_share numeric      not null,  -- NAV per share (raw, no decimals)
  total_assets numeric      not null,  -- totalAssets() at snapshot
  hodl_nav     numeric      not null,  -- HODL baseline at same timestamp (same asset price)
  alpha_pct    numeric      not null,  -- (nav_per_share - hodl_nav) / hodl_nav * 100
  created_at   timestamptz not null default now()
);

alter table public.vault_nav_history enable row level security;

-- Public read (for frontend charts)
drop policy if exists "vault_nav_history_read_all" on public.vault_nav_history;
create policy "vault_nav_history_read_all"
  on public.vault_nav_history for select using (true);

-- Only service role writes
drop policy if exists "vault_nav_history_insert_service" on public.vault_nav_history;
create policy "vault_nav_history_insert_service"
  on public.vault_nav_history for insert with check (true);

-- Indexes for chart queries
drop index if exists vault_nav_history_vault_idx;
drop index if exists vault_nav_history_time_idx;
create index vault_nav_history_vault_idx  on public.vault_nav_history(vault_symbol);
create index vault_nav_history_time_idx  on public.vault_nav_history(snapshot_at desc);

-- ─── Deposit / Withdrawal Flow ───────────────────────────────
-- Tracks net deposit/withdrawal volume per vault per day
drop table if exists public.vault_flow;

create table public.vault_flow (
  id            text        primary key default uuid_generate_v4(),
  vault_symbol  text        not null,
  date          date        not null,
  deposits      numeric     not null default 0,
  withdrawals   numeric     not null default 0,
  net_flow     numeric     not null default 0,  -- deposits - withdrawals
  tx_count     integer     not null default 0,
  created_at   timestamptz not null default now()
);

alter table public.vault_flow enable row level security;

drop policy if exists "vault_flow_read_all" on public.vault_flow;
create policy "vault_flow_read_all"
  on public.vault_flow for select using (true);

drop policy if exists "vault_flow_insert_service" on public.vault_flow;
create policy "vault_flow_insert_service"
  on public.vault_flow for insert with check (true);

drop index if exists vault_flow_vault_date_idx;
create index vault_flow_vault_date_idx on public.vault_flow(vault_symbol, date desc);

-- ─── Performance Snapshots ────────────────────────────────
-- Aggregated performance metrics per vault per day
drop table if exists public.vault_performance;

create table public.vault_performance (
  id                text        primary key default uuid_generate_v4(),
  vault_symbol      text        not null,
  date              date        not null,
  nav_return_pct    numeric     not null,  -- daily NAV return %
  hodl_return_pct   numeric     not null,  -- daily HODL return %
  alpha_pct         numeric     not null,  -- nav_return - hodl_return
  cumulative_alpha   numeric     not null,  -- running alpha vs HODL since vault launch
  max_drawdown_pct  numeric     not null,  -- max drawdown from peak NAV
  win_rate_pct      numeric     not null,  -- % of positive alpha days
  sharpe_ratio      numeric     not null,  -- simplified Sharpe (alpha / std dev)
  created_at         timestamptz not null default now()
);

alter table public.vault_performance enable row level security;

drop policy if exists "vault_performance_read_all" on public.vault_performance;
create policy "vault_performance_read_all"
  on public.vault_performance for select using (true);

drop policy if exists "vault_performance_insert_service" on public.vault_performance;
create policy "vault_performance_insert_service"
  on public.vault_performance for insert with check (true);

drop index if exists vault_performance_vault_date_idx;
create index vault_performance_vault_date_idx on public.vault_performance(vault_symbol, date desc);
