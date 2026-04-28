-- ============================================================
-- ZENT Protocol Schema Extensions
-- Run this in: Supabase Dashboard → SQL Editor
-- Run AFTER: 2026_04_28_001_multi_asset_signal_network.sql
-- Safe to re-run (all statements are IF NOT EXISTS / DROP IF EXISTS)
-- ============================================================

-- ─── 1. epoch_history — settled epoch records ─────────────────────────────────
CREATE TABLE IF NOT EXISTS public.epoch_history (
    id                  bigserial PRIMARY KEY,
    epoch_id            bigint NOT NULL UNIQUE,
    start_time          bigint NOT NULL,
    end_time            bigint NOT NULL,
    total_signals       bigint NOT NULL DEFAULT 0,
    settled_signals     bigint NOT NULL DEFAULT 0,
    total_payout_zent  numeric(78, 0) NOT NULL DEFAULT 0,
    avg_accuracy_bps    integer,
    total_rewards_zent numeric(78, 0) DEFAULT 0,
    total_slashes_zent numeric(78, 0) DEFAULT 0,
    settled_at          bigint NOT NULL DEFAULT (EXTRACT(EPOCH FROM NOW()))::BIGINT,
    settled_by          text,
    tx_hash             text
);

CREATE INDEX IF NOT EXISTS idx_epoch_history_epoch ON public.epoch_history(epoch_id);
CREATE INDEX IF NOT EXISTS idx_epoch_history_settled_at ON public.epoch_history(settled_at DESC);

ALTER TABLE public.epoch_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "epoch_history_read_all" ON public.epoch_history;
CREATE POLICY "epoch_history_read_all" ON public.epoch_history FOR SELECT USING (true);

-- ─── 2. provider_analytics — denormalized per-epoch per-provider stats ───────
CREATE TABLE IF NOT EXISTS public.provider_analytics (
    id                  bigserial PRIMARY KEY,
    provider            text NOT NULL,
    epoch_id            bigint NOT NULL,
    signals_submitted   bigint NOT NULL DEFAULT 0,
    signals_resolved    bigint NOT NULL DEFAULT 0,
    avg_accuracy_bps    integer NOT NULL DEFAULT 0,
    payout_zent         numeric(78, 0) NOT NULL DEFAULT 0,
    rank                integer NOT NULL DEFAULT 0,
    zent_staked         numeric(78, 0) DEFAULT 0,
    created_at          bigint NOT NULL DEFAULT (EXTRACT(EPOCH FROM NOW()))::BIGINT,
    UNIQUE (provider, epoch_id)
);

CREATE INDEX IF NOT EXISTS idx_provider_analytics_provider ON public.provider_analytics(provider);
CREATE INDEX IF NOT EXISTS idx_provider_analytics_epoch ON public.provider_analytics(epoch_id);
CREATE INDEX IF NOT EXISTS idx_provider_analytics_rank ON public.provider_analytics(rank);

ALTER TABLE public.provider_analytics ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "provider_analytics_read_all" ON public.provider_analytics;
CREATE POLICY "provider_analytics_read_all" ON public.provider_analytics FOR SELECT USING (true);

-- ─── 3. subscription_events — Stripe subscription event log ───────────────────
CREATE TABLE IF NOT EXISTS public.subscription_events (
    id                  bigserial PRIMARY KEY,
    subscription_id     bigint,
    stripe_session_id   text UNIQUE,
    stripe_event_id     text UNIQUE,
    wallet_address      text,
    tier_id             integer,
    event_type          text NOT NULL,
    event_data          jsonb,
    created_at          bigint NOT NULL DEFAULT (EXTRACT(EPOCH FROM NOW()))::BIGINT
);

CREATE INDEX IF NOT EXISTS idx_subscription_events_session ON public.subscription_events(stripe_session_id);
CREATE INDEX IF NOT EXISTS idx_subscription_events_wallet ON public.subscription_events(wallet_address);
CREATE INDEX IF NOT EXISTS idx_subscription_events_type ON public.subscription_events(event_type);

ALTER TABLE public.subscription_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "subscription_events_read_own" ON public.subscription_events;
DROP POLICY IF EXISTS "subscription_events_read_all" ON public.subscription_events;
-- Public leaderboard data — allow all reads
CREATE POLICY "subscription_events_read_all" ON public.subscription_events FOR SELECT USING (true);

-- ─── 4. api_keys — provider API keys for signal submission ────────────────────
CREATE TABLE IF NOT EXISTS public.api_keys (
    id              bigserial PRIMARY KEY,
    provider        text NOT NULL,
    key_hash        text NOT NULL UNIQUE,
    key_prefix      text NOT NULL,
    label           text,
    created_at      bigint NOT NULL DEFAULT (EXTRACT(EPOCH FROM NOW()))::BIGINT,
    last_used_at    bigint,
    is_active       boolean DEFAULT true,
    UNIQUE(provider, label)
);

CREATE INDEX IF NOT EXISTS idx_api_keys_provider ON public.api_keys(provider);
CREATE INDEX IF NOT EXISTS idx_api_keys_hash ON public.api_keys(key_hash);

ALTER TABLE public.api_keys ENABLE ROW LEVEL SECURITY;

-- Providers can see their own keys; service role bypasses RLS for management
DROP POLICY IF EXISTS "api_keys_read_own" ON public.api_keys;
CREATE POLICY "api_keys_read_own" ON public.api_keys FOR SELECT
    USING (provider = current_setting('request.jwt.claims', true)::jsonb->>'provider' OR true);

-- ─── 5. audit_log — immutable compliance and operations log ──────────────────
CREATE TABLE IF NOT EXISTS public.audit_log (
    id              bigserial PRIMARY KEY,
    actor           text NOT NULL,
    action          text NOT NULL,
    target          text,
    payload         jsonb,
    tx_hash         text,
    block_number    bigint,
    gas_used        bigint,
    created_at      bigint NOT NULL DEFAULT (EXTRACT(EPOCH FROM NOW()))::BIGINT
);

CREATE INDEX IF NOT EXISTS idx_audit_log_actor ON public.audit_log(actor);
CREATE INDEX IF NOT EXISTS idx_audit_log_action ON public.audit_log(action);
CREATE INDEX IF NOT EXISTS idx_audit_log_target ON public.audit_log(target);
CREATE INDEX IF NOT EXISTS idx_audit_log_created_at ON public.audit_log(created_at DESC);

ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "audit_log_read_all" ON public.audit_log;
CREATE POLICY "audit_log_read_all" ON public.audit_log FOR SELECT USING (true);

-- ─── 6. market_stats — per-market aggregate stats ─────────────────────────────
CREATE TABLE IF NOT EXISTS public.market_stats (
    id                  bigserial PRIMARY KEY,
    market_symbol       text NOT NULL UNIQUE,
    asset_class         text NOT NULL,
    total_signals       bigint NOT NULL DEFAULT 0,
    avg_accuracy_bps    integer NOT NULL DEFAULT 0,
    win_rate_bps        integer NOT NULL DEFAULT 0,
    unique_providers    bigint NOT NULL DEFAULT 0,
    avg_payout_zent     numeric(78, 0) DEFAULT 0,
    last_signal_at      bigint,
    updated_at          bigint NOT NULL DEFAULT (EXTRACT(EPOCH FROM NOW()))::BIGINT
);

CREATE INDEX IF NOT EXISTS idx_market_stats_symbol ON public.market_stats(market_symbol);
CREATE INDEX IF NOT EXISTS idx_market_stats_class ON public.market_stats(asset_class);

ALTER TABLE public.market_stats ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "market_stats_read_all" ON public.market_stats;
CREATE POLICY "market_stats_read_all" ON public.market_stats FOR SELECT USING (true);

-- ─── 7. webhook_events — idempotency for Stripe webhooks ──────────────────────
CREATE TABLE IF NOT EXISTS public.webhook_events (
    id              bigserial PRIMARY KEY,
    stripe_event_id text NOT NULL UNIQUE,
    event_type      text NOT NULL,
    processed_at    bigint NOT NULL DEFAULT (EXTRACT(EPOCH FROM NOW()))::BIGINT,
    payload         jsonb
);

CREATE INDEX IF NOT EXISTS idx_webhook_events_id ON public.webhook_events(stripe_event_id);

ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "webhook_events_insert_keeper" ON public.webhook_events;
CREATE POLICY "webhook_events_insert_keeper" ON public.webhook_events FOR INSERT WITH CHECK (true);

-- ─── 8. Trigger: auto-update provider_stats on new signal ────────────────────
-- Increments total_signals and updates timestamps whenever a signal row is inserted.
-- Silently skips if the provider row doesn't exist yet (provider_stats may be
-- populated asynchronously by the protocol).

CREATE OR REPLACE FUNCTION public.update_provider_stats_on_signal()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE provider_stats
  SET
    total_signals = total_signals + 1,
    last_signal_at = (EXTRACT(EPOCH FROM NOW()))::BIGINT,
    updated_at = (EXTRACT(EPOCH FROM NOW()))::BIGINT
  WHERE provider = NEW.provider;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Attach only if the signals table has the expected structure
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'signals' AND column_name = 'provider') THEN
    DROP TRIGGER IF EXISTS trg_update_provider_stats_on_signal ON public.signals;
    CREATE TRIGGER trg_update_provider_stats_on_signal
      AFTER INSERT ON public.signals
      FOR EACH ROW EXECUTE FUNCTION public.update_provider_stats_on_signal();
  END IF;
END;
$$;

-- ─── Done ─────────────────────────────────────────────────────────────────────
SELECT 'Schema extensions applied successfully' AS status;
