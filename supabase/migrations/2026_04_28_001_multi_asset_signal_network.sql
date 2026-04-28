-- ============================================================
-- Zentory Multi-Asset Signal Network Migration
-- Run this in: Supabase Dashboard → SQL Editor
-- Safe to re-run (all statements are IF NOT EXISTS / IF NOT EXISTS
-- ============================================================

-- ─── 1. signals table — add multi-asset columns ─────────────────────────────────
ALTER TABLE public.signals ADD COLUMN IF NOT EXISTS asset_class TEXT NOT NULL DEFAULT 'CRYPTO_PERP';
ALTER TABLE public.signals ADD COLUMN IF NOT EXISTS asset_id TEXT NOT NULL DEFAULT 'CRYPTO:BTC';
ALTER TABLE public.signals ADD COLUMN IF NOT EXISTS chain_id BIGINT;
ALTER TABLE public.signals ADD COLUMN IF NOT EXISTS accuracy_bps INTEGER;
ALTER TABLE public.signals ADD COLUMN IF NOT EXISTS payout_zent NUMERIC(78, 0);
ALTER TABLE public.signals ADD COLUMN IF NOT EXISTS expires_at BIGINT;
ALTER TABLE public.signals ADD COLUMN IF NOT EXISTS nonce BIGINT DEFAULT 0;
ALTER TABLE public.signals ADD COLUMN IF NOT EXISTS signal_hash TEXT;
ALTER TABLE public.signals ADD COLUMN IF NOT EXISTS provider_ve_balance NUMERIC(78, 0);

CREATE INDEX IF NOT EXISTS idx_signals_asset_class ON public.signals(asset_class);
CREATE INDEX IF NOT EXISTS idx_signals_asset_id ON public.signals(asset_id);
CREATE INDEX IF NOT EXISTS idx_signals_provider ON public.signals(provider);
CREATE INDEX IF NOT EXISTS idx_signals_provider_ve_balance ON public.signals(provider_ve_balance);
CREATE INDEX IF NOT EXISTS idx_signals_expires_at ON public.signals(expires_at);

-- ─── 2. signal_scores — per-epoch accuracy tracking ─────────────────────────────
CREATE TABLE IF NOT EXISTS public.signal_scores (
    id            bigserial primary key,
    signal_id     text      not null references public.signals(id) on delete cascade,
    epoch_id      bigint    not null,
    accuracy_bps  integer   not null,
    payout_zent   numeric(78, 0) not null,
    scored_at     bigint    not null default (EXTRACT(EPOCH FROM NOW()))::BIGINT,
    scored_by     text,
    unique (signal_id, epoch_id)
);

CREATE INDEX IF NOT EXISTS idx_signal_scores_epoch ON public.signal_scores(epoch_id);
CREATE INDEX IF NOT EXISTS idx_signal_scores_signal ON public.signal_scores(signal_id);

ALTER TABLE public.signal_scores ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "signal_scores_read_all" ON public.signal_scores;
CREATE POLICY "signal_scores_read_all" ON public.signal_scores FOR SELECT USING (true);

DROP POLICY IF EXISTS "signal_scores_insert_keeper" ON public.signal_scores;
CREATE POLICY "signal_scores_insert_keeper" ON public.signal_scores FOR INSERT WITH CHECK (true);

-- ─── 3. provider_stats — live provider rankings ─────────────────────────────────
CREATE TABLE IF NOT EXISTS public.provider_stats (
    id                  bigserial primary key,
    provider            text     not null unique,
    total_signals       bigint  default 0,
    resolved_signals    bigint  default 0,
    avg_accuracy_bps    integer default 0,
    total_payout_zent   numeric(78, 0) default 0,
    current_rank        integer default 0,
    last_signal_at      bigint,
    updated_at          bigint  not null default (EXTRACT(EPOCH FROM NOW()))::BIGINT
);

CREATE INDEX IF NOT EXISTS idx_provider_stats_rank ON public.provider_stats(current_rank);
CREATE INDEX IF NOT EXISTS idx_provider_stats_provider ON public.provider_stats(provider);

ALTER TABLE public.provider_stats ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "provider_stats_read_all" ON public.provider_stats;
CREATE POLICY "provider_stats_read_all" ON public.provider_stats FOR SELECT USING (true);

DROP POLICY IF EXISTS "provider_stats_insert_keeper" ON public.provider_stats;
CREATE POLICY "provider_stats_insert_keeper" ON public.provider_stats FOR INSERT WITH CHECK (true);

-- ─── 4. subscriptions — ERC-6932 subscription tracking ──────────────────────────
CREATE TABLE IF NOT EXISTS public.subscriptions (
    id                bigserial primary key,
    subscriber        text      not null,
    tier_id           integer  not null,
    tier_name         text     not null,
    token_id          bigint,
    asset_class_bitmap text    not null,
    expiration        bigint   not null,
    zent_paid         numeric(78, 0) not null,
    subscribed_at     bigint   not null default (EXTRACT(EPOCH FROM NOW()))::BIGINT,
    cancelled_at      bigint,
    refund_zent       numeric(78, 0)
);

CREATE INDEX IF NOT EXISTS idx_subscriptions_subscriber ON public.subscriptions(subscriber);
CREATE INDEX IF NOT EXISTS idx_subscriptions_expiration ON public.subscriptions(expiration);
CREATE INDEX IF NOT EXISTS idx_subscriptions_subscriber_expiration ON public.subscriptions(subscriber, expiration);

ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "subscriptions_read_all" ON public.subscriptions;
CREATE POLICY "subscriptions_read_all" ON public.subscriptions FOR SELECT USING (true);

DROP POLICY IF EXISTS "subscriptions_insert_keeper" ON public.subscriptions;
CREATE POLICY "subscriptions_insert_keeper" ON public.subscriptions FOR INSERT WITH CHECK (true);

-- ─── 5. epochs — epoch windows for EpochScoring ────────────────────────────────
CREATE TABLE IF NOT EXISTS public.epochs (
    id              bigserial primary key,
    epoch_id        bigint    not null unique,
    start_time      bigint    not null,
    end_time        bigint    not null,
    total_signals   integer   default 0,
    settled_signals integer   default 0,
    settled         boolean   default false,
    settled_at      bigint
);

CREATE INDEX IF NOT EXISTS idx_epochs_settled ON public.epochs(settled) WHERE NOT settled;

ALTER TABLE public.epochs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "epochs_read_all" ON public.epochs;
CREATE POLICY "epochs_read_all" ON public.epochs FOR SELECT USING (true);

DROP POLICY IF EXISTS "epochs_insert_keeper" ON public.epochs;
CREATE POLICY "epochs_insert_keeper" ON public.epochs FOR INSERT WITH CHECK (true);

-- ─── 6. cross_chain_signal_records — CCIP cross-chain signals ───────────────────
CREATE TABLE IF NOT EXISTS public.cross_chain_signal_records (
    id                     bigserial primary key,
    signal_id              text      not null,
    source_chain_id        bigint    not null,
    destination_chain_id   bigint,
    ccip_message_id        text,
    ccip_status            text,
    sent_at                bigint    not null default (EXTRACT(EPOCH FROM NOW()))::BIGINT,
    received_at            bigint
);

CREATE INDEX IF NOT EXISTS idx_cc_records_signal ON public.cross_chain_signal_records(signal_id);
CREATE INDEX IF NOT EXISTS idx_cc_records_status ON public.cross_chain_signal_records(ccip_status);

ALTER TABLE public.cross_chain_signal_records ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "cross_chain_signal_records_read_all" ON public.cross_chain_signal_records;
CREATE POLICY "cross_chain_signal_records_read_all" ON public.cross_chain_signal_records FOR SELECT USING (true);

DROP POLICY IF EXISTS "cross_chain_signal_records_insert_keeper" ON public.cross_chain_signal_records;
CREATE POLICY "cross_chain_signal_records_insert_keeper" ON public.cross_chain_signal_records FOR INSERT WITH CHECK (true);

-- ─── Done ───────────────────────────────────────────────────────────────────────
SELECT 'Multi-asset schema applied successfully' as status;
