-- ============================================================
-- Zentory Protocol — Supabase Schema (fully idempotent)
-- Run this in: Supabase Dashboard → SQL Editor
-- Safe to re-run: drops and recreates every object
-- ============================================================

-- ─── Signals ───────────────────────────────────────────────
create extension if not exists "uuid-ossp";

create table if not exists public.signals (
  id           text        primary key default uuid_generate_v4(),
  created_at   timestamptz not null default now(),
  provider     text        not null,
  asset        text        not null,
  direction    text        not null,
  size         numeric     not null,
  price        numeric     not null,
  status       text        not null default 'pending',
  tx_hash      text,
  executed_by  text,
  executor_address text
);

-- Trigger (idempotent via CREATE OR REPLACE)
create or replace function public.handle_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists signals_updated_at on public.signals;
create trigger signals_updated_at
  before update on public.signals
  for each row execute function public.handle_updated_at();

alter table public.signals enable row level security;

drop policy if exists "signals_read_all" on public.signals;
create policy "signals_read_all"
  on public.signals for select using (true);

drop policy if exists "signals_insert_keeper" on public.signals;
create policy "signals_insert_keeper"
  on public.signals for insert with check (true);

drop policy if exists "signals_update_keeper" on public.signals;
create policy "signals_update_keeper"
  on public.signals for update using (true);

-- ─── Profiles ──────────────────────────────────────────────
create table if not exists public.profiles (
  wallet_address   text        primary key,
  email            text        unique,
  created_at       timestamptz not null default now(),
  is_keeper        boolean     not null default false,
  is_governor      boolean     not null default false
);

alter table public.profiles enable row level security;

drop policy if exists "profiles_read_all" on public.profiles;
create policy "profiles_read_all"
  on public.profiles for select using (true);

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own"
  on public.profiles for insert with check (true);

-- ─── Governance Proposals ───────────────────────────────────
create table if not exists public.proposals (
  id                text        primary key default uuid_generate_v4(),
  proposal_id       integer     not null unique,
  title             text        not null,
  description       text        not null,
  status            text        not null default 'active',
  votes_for         numeric     not null default 0,
  votes_against     numeric     not null default 0,
  quorum_required   numeric     not null default 0,
  created_at        timestamptz not null default now()
);

alter table public.proposals enable row level security;

drop policy if exists "proposals_read_all" on public.proposals;
create policy "proposals_read_all"
  on public.proposals for select using (true);

-- ─── Keeper Audit Log ──────────────────────────────────────
create table if not exists public.keeper_audit (
  id                text        primary key default uuid_generate_v4(),
  signal_id         text        references public.signals(id) on delete set null,
  tx_hash           text        not null,
  gas_used          numeric,
  executor_address   text,
  block_number      bigint,
  created_at        timestamptz not null default now()
);

alter table public.keeper_audit enable row level security;

drop policy if exists "keeper_audit_read_all" on public.keeper_audit;
create policy "keeper_audit_read_all"
  on public.keeper_audit for select using (true);

drop policy if exists "keeper_audit_insert_keeper" on public.keeper_audit;
create policy "keeper_audit_insert_keeper"
  on public.keeper_audit for insert with check (true);

-- ─── Indexes ───────────────────────────────────────────────
create index if not exists signals_asset_idx       on public.signals(asset);
create index if not exists signals_status_idx     on public.signals(status);
create index if not exists signals_provider_idx    on public.signals(provider);
create index if not exists signals_created_idx    on public.signals(created_at desc);
create index if not exists keeper_audit_created_idx on public.keeper_audit(created_at desc);
create index if not exists keeper_audit_signal_idx on public.keeper_audit(signal_id);

-- ─── Whitelist / Waitlist ─────────────────────────────────
create table if not exists public.whitelist (
  id         text        primary key default uuid_generate_v4(),
  email      text        not null unique,
  source     text        not null default 'website',
  created_at timestamptz not null default now()
);

alter table public.whitelist enable row level security;

drop policy if exists "whitelist_insert_public" on public.whitelist;
create policy "whitelist_insert_public"
  on public.whitelist for insert with check (true);

drop policy if exists "whitelist_read_admin" on public.whitelist;
create policy "whitelist_read_admin"
  on public.whitelist for select using (true);

create index if not exists whitelist_email_idx on public.whitelist(email);
create index if not exists whitelist_created_idx on public.whitelist(created_at desc);
