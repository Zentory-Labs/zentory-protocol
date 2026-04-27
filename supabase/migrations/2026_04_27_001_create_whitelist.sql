-- ============================================================
-- Zentory Protocol — Whitelist Migration (fully idempotent)
-- Safe to re-run: drops and recreates cleanly
-- ============================================================

drop table if exists public.whitelist;

create table public.whitelist (
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

drop index if exists whitelist_email_idx;
drop index if exists whitelist_created_idx;
create index whitelist_email_idx on public.whitelist(email);
create index whitelist_created_idx on public.whitelist(created_at desc);
