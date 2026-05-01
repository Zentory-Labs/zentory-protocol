-- ============================================================
-- Performance Indexes for ZENTORY Labs
-- Phase 2: Fix full-table scans on common query patterns
-- Run in: Supabase Dashboard → SQL Editor
-- Uses CONCURRENTLY to avoid locking tables in production
-- ============================================================

-- ─── Signals table ───────────────────────────────────────
-- Fixes: SELECT * FROM signals ORDER BY created_at DESC LIMIT 20
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_signals_created_at
  ON public.signals(created_at DESC);

-- Fixes: multi-asset provider lookups (provider_address column added in 001)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_signals_provider_asset
  ON public.signals(provider_address, asset_class);

-- Fixes: provider analytics per epoch (epoch_id is the column name)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_signals_epoch
  ON public.signals(epoch_id);

-- ─── Subscriptions table ─────────────────────────────────
-- Fixes: SELECT * FROM subscriptions WHERE user_id = $1 AND status = 'active'
-- Note: user_id is named "subscriber" in schema; status column does not exist
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_subscriptions_user_active
  ON public.subscriptions(subscriber, tier_id) WHERE tier_id IS NOT NULL;

-- Fixes: tier-based subscription filtering
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_subscriptions_tier
  ON public.subscriptions(tier_id);

-- ─── Epochs table ─────────────────────────────────────────
-- Fixes: SELECT * FROM epochs WHERE start_time > $1 AND end_time < $2
-- No index currently exists on (start_time, end_time)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_epochs_time_range
  ON public.epochs(start_time, end_time);

-- Fixes: active/open epoch lookups
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_epochs_status
  ON public.epochs(status);

-- ─── Audit Log table ──────────────────────────────────────
-- Fixes: SELECT * FROM audit_logs WHERE keeper_address = $1 AND created_at > $2
-- Note: keeper_address is named "actor" in schema; no keeper_address column exists
-- Indexing actor + created_at for keeper-equivalent lookups
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_audit_log_actor_time
  ON public.audit_log(actor, created_at DESC);

-- Fixes: action-based audit log filtering with time ordering
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_audit_log_action_time
  ON public.audit_log(action, created_at DESC);

-- ─── Vault NAV History table ──────────────────────────────
-- Fixes: chart queries filtering by vault + time range
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_vault_nav_history_vault_time
  ON public.vault_nav_history(vault_symbol, snapshot_at DESC);

-- ─── Vault Performance table ───────────────────────────────
-- Fixes: performance queries by vault + date range
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_vault_performance_vault_date
  ON public.vault_performance(vault_symbol, date DESC);

-- ─── Vault Flow table ──────────────────────────────────────
-- Fixes: flow queries by vault + date (composite already exists; add DESC variant)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_vault_flow_vault_date
  ON public.vault_flow(vault_symbol, date DESC);

-- ─── Provider Stats table ─────────────────────────────────
-- Fixes: ranking by total_score (live leaderboard)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_provider_stats_score
  ON public.provider_stats(total_score DESC);

-- Fixes: provider stats lookup per epoch
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_provider_stats_epoch
  ON public.provider_stats(last_signal_at DESC);

-- ─── Provider Analytics table ─────────────────────────────
-- Fixes: epoch-based analytics aggregation
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_provider_analytics_epoch_provider
  ON public.provider_analytics(epoch_id, provider);

-- ─── Cross-chain Signal Records table ─────────────────────
-- Fixes: signal lookup by CCIP message ID
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_cross_chain_signal_records_message
  ON public.cross_chain_signal_records(ccip_message_id);

-- ─── Market Stats table ────────────────────────────────────
-- Fixes: market stats lookup by asset class + last update
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_market_stats_class_updated
  ON public.market_stats(asset_class, updated_at DESC);

-- ─── Signal Scores table ───────────────────────────────────
-- Fixes: score lookups per epoch ordered by accuracy
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_signal_scores_epoch_accuracy
  ON public.signal_scores(epoch_id, accuracy_bps DESC);

-- ─── Done ─────────────────────────────────────────────────
SELECT 'Performance indexes applied successfully' AS status;
