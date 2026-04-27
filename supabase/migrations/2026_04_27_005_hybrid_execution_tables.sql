-- Hybrid execution pipeline tables (testnet → prod)
-- Idempotent-ish: safe to re-run in Supabase SQL editor.

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

create index if not exists execution_attempts_created_idx
  on public.execution_attempts (created_at desc);

create table if not exists public.hl_user_fills (
  id bigserial primary key,
  -- NOTE: intentionally not FK-constrained so ingestion can run before mapping rows exist.
  vault_address text not null,
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

create index if not exists hl_user_fills_time_idx
  on public.hl_user_fills (vault_address, time_ms desc);

create index if not exists hl_user_fills_hl_user_idx
  on public.hl_user_fills (hl_user_address, time_ms desc);
