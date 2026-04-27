-- ============================================================
-- Zentory Protocol — Seed Vault NAV History
-- Generates 30 days of realistic NAV history per vault
-- Run AFTER 2026_04_27_003_create_vault_nav_history.sql
-- ============================================================

-- Wipe existing seed data
delete from public.vault_nav_history;
delete from public.vault_flow;
delete from public.vault_performance;

-- ─── Seed vault_nav_history ───────────────────────────────────
-- Timeline: 2026-03-28 to 2026-04-27 (30 days, every 4 hours = ~180 snapshots/vault)
do $$
declare
  vault_rec record;
  day_offset integer;
  hour_offset integer;
  nav_base numeric;
  hodl_base numeric;
  alpha_base numeric;
  nav_current numeric;
  hodl_current numeric;
  snapshot_ts timestamptz;
  alpha_pct numeric;
begin
  for vault_rec in
    select symbol, initial_nav, daily_drift, vol from (values
      ('zETH', 3420.0, 0.0012, 0.018),
      ('zBTC', 96500.0, 0.0015, 0.022),
      ('zSOL',  140.0, 0.0025, 0.035),
      ('zXRP',    2.30, 0.0018, 0.028)
    ) as t(symbol, initial_nav, daily_drift, vol)
  loop
    nav_current := vault_rec.initial_nav;
    hodl_current := vault_rec.initial_nav;

    -- Generate 30 days of 4-hourly snapshots
    for day_offset in 0..29 loop
      for hour_offset in 0..5 loop
        snapshot_ts := make_timestamptz(2026, 3, 28, 0, 0, 0)
          + (day_offset || ' days')::interval
          + (hour_offset * 4 || ' hours')::interval;

        -- Random walk for both NAV and HODL
        hodl_current := hodl_current * (1 + (random() - 0.48) * vault_rec.vol);
        nav_current := nav_current * (1 + (random() - 0.44) * vault_rec.vol * 1.3); -- GP slightly outperforms

        alpha_pct := round(((nav_current - hodl_current) / hodl_current * 100)::numeric, 4);

        insert into public.vault_nav_history
          (vault_symbol, snapshot_at, nav_per_share, total_assets, hodl_nav, alpha_pct)
        values (
          vault_rec.symbol,
          snapshot_ts,
          -- nav_per_share stored as raw with 18 decimals (multiply for display)
          (nav_current * 1e18)::numeric,
          (nav_current * 250000 * 1e18)::numeric,  -- 250k shares * nav
          (hodl_current * 1e18)::numeric,
          alpha_pct
        );
      end loop;
    end loop;
  end loop;
end;
$$;

-- ─── Seed vault_flow ──────────────────────────────────────────
-- 30 days of realistic deposit/withdrawal patterns
do $$
declare
  vault_rec record;
  day_offset integer;
  flow_date date;
  deposits numeric;
  withdrawals numeric;
begin
  for vault_rec in
    select symbol, base_deposits from (values
      ('zETH', 5000), ('zBTC', 50), ('zSOL', 8000), ('zXRP', 500000)
    ) as t(symbol, base_deposits)
  loop
    for day_offset in 0..29 loop
      flow_date := date '2026-03-28' + day_offset;

      -- Realistic deposit pattern: weekdays 2x, weekends half
      deposits := vault_rec.base_deposits * (0.5 + random() * 1.5);
      if extract(dow from flow_date) in (0, 6) then
        deposits := deposits * 0.5;
      end if;

      -- Withdrawals: smaller, spike after large deposit days
      withdrawals := deposits * (0.1 + random() * 0.3);

      insert into public.vault_flow (vault_symbol, date, deposits, withdrawals, net_flow, tx_count)
      values (
        vault_rec.symbol,
        flow_date,
        deposits,
        withdrawals,
        deposits - withdrawals,
        floor(5 + random() * 20)::int
      );
    end loop;
  end loop;
end;
$$;

-- ─── Seed vault_performance ───────────────────────────────────
-- Daily performance metrics per vault
do $$
declare
  vault_rec record;
  day_offset integer;
  perf_date date;
  prev_nav numeric;
  curr_nav numeric;
  prev_hodl numeric;
  curr_hodl numeric;
  nav_ret numeric;
  hodl_ret numeric;
  alpha numeric;
  alpha_pct numeric;
  pos_days integer := 0;
  total_days integer := 0;
  alpha_sum numeric := 0;
  alpha_sq_sum numeric := 0;
begin
  for vault_rec in
    select symbol, initial_nav from (values
      ('zETH', 3420.0), ('zBTC', 96500.0), ('zSOL', 140.0), ('zXRP', 2.30)
    ) as t(symbol, initial_nav)
  loop
    prev_nav := vault_rec.initial_nav;
    prev_hodl := vault_rec.initial_nav;
    pos_days := 0;
    total_days := 0;
    alpha_sum := 0;
    alpha_sq_sum := 0;

    for day_offset in 0..29 loop
      perf_date := date '2026-03-28' + day_offset;

      curr_hodl := prev_hodl * (1 + (random() - 0.48) * 0.03);
      curr_nav := prev_nav * (1 + (random() - 0.44) * 0.035);

      nav_ret := (curr_nav - prev_nav) / prev_nav * 100;
      hodl_ret := (curr_hodl - prev_hodl) / prev_hodl * 100;
      alpha := nav_ret - hodl_ret;

      if alpha > 0 then pos_days := pos_days + 1; end if;
      total_days := total_days + 1;
      alpha_sum := alpha_sum + alpha;
      alpha_sq_sum := alpha_sq_sum + (alpha * alpha);

      insert into public.vault_performance
        (vault_symbol, date, nav_return_pct, hodl_return_pct, alpha_pct, cumulative_alpha, max_drawdown_pct, win_rate_pct, sharpe_ratio)
      values (
        vault_rec.symbol,
        perf_date,
        round(nav_ret::numeric, 4),
        round(hodl_ret::numeric, 4),
        round(alpha::numeric, 4),
        round((curr_nav - vault_rec.initial_nav) / vault_rec.initial_nav * 100::numeric, 4),
        round((random() * 5)::numeric, 2),
        round((pos_days::numeric / total_days * 100)::numeric, 2),
        coalesce(round((alpha_sum / nullif(sqrt(nullif(alpha_sq_sum - (alpha_sum * alpha_sum / nullif(total_days, 0)), 0)), 0))::numeric, 2), 0)
      );

      prev_nav := curr_nav;
      prev_hodl := curr_hodl;
    end loop;
  end loop;
end;
$$;

-- ─── Verify ─────────────────────────────────────────────────
select vault_symbol, count(*) as snapshots, min(snapshot_at), max(snapshot_at)
from public.vault_nav_history
group by vault_symbol
order by vault_symbol;

select vault_symbol, min(deposits)::int as min_daily_deposit, max(deposits)::int as max_daily_deposit, sum(deposits)::int as total_deposits
from public.vault_flow
group by vault_symbol
order by vault_symbol;

select vault_symbol, count(*) as days, round(avg(alpha_pct)::numeric, 3) as avg_alpha_pct, max(win_rate_pct) as win_rate
from public.vault_performance
group by vault_symbol
order by vault_symbol;
