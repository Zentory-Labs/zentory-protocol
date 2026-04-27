-- RLS: public read for dashboard + anon client (matches signals pattern)

alter table if exists public.vault_trading_accounts enable row level security;
alter table if exists public.execution_attempts enable row level security;
alter table if exists public.hl_user_fills enable row level security;

drop policy if exists "vault_trading_accounts_read_all" on public.vault_trading_accounts;
create policy "vault_trading_accounts_read_all"
  on public.vault_trading_accounts for select using (true);

drop policy if exists "execution_attempts_read_all" on public.execution_attempts;
create policy "execution_attempts_read_all"
  on public.execution_attempts for select using (true);

drop policy if exists "hl_user_fills_read_all" on public.hl_user_fills;
create policy "hl_user_fills_read_all"
  on public.hl_user_fills for select using (true);
