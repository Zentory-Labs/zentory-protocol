-- ============================================================
-- RLS FIX: ZENTORY Labs Production Security Hardening
-- Phase 2 — fixes broken/missing policies found in Phase 1 audit
--
-- Tables confirmed present in migrations:
--   whitelist, signals, vault_nav_history, vault_flow,
--   vault_performance, vault_trading_accounts, execution_attempts,
--   hl_user_fills, signal_scores, provider_stats, subscriptions,
--   epochs, cross_chain_signal_records, epoch_history,
--   provider_analytics, subscription_events, api_keys, audit_log,
--   market_stats, webhook_events
--
-- Tables referenced in spec but NOT found in migrations (SKIPPED):
--   profiles  — never created; auth.users is the source of truth
--   research  — never created
--   keeper_audit — referenced in seed but never created
--   vault_positions — never created
-- ============================================================

-- ─── 1. SIGNALS TABLE ───────────────────────────────────────
-- Reads: public   (transparency, leaderboard)
-- Inserts: authenticated users submit via API keys (enforced at app level)
-- Updates: only the original provider_address
ALTER TABLE public.signals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Signals are viewable by everyone" ON public.signals;
CREATE POLICY "Signals are viewable by everyone"
  ON public.signals FOR SELECT USING (true);

DROP POLICY IF EXISTS "Authenticated users can submit signals" ON public.signals;
CREATE POLICY "Authenticated users can submit signals"
  ON public.signals FOR INSERT WITH CHECK (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "Users can update own signals" ON public.signals;
CREATE POLICY "Users can update own signals"
  ON public.signals FOR UPDATE USING (auth.uid()::text = provider);

-- ─── 2. SUBSCRIPTIONS TABLE ─────────────────────────────────
-- Reads: users can only see their own subscription
-- Writes: service_role only (via Stripe webhook / backend)
-- Column is 'subscriber' (wallet address text), NOT 'user_id'
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own subscription" ON public.subscriptions;
CREATE POLICY "Users can view own subscription"
  ON public.subscriptions FOR SELECT USING (auth.uid()::text = subscriber);

DROP POLICY IF EXISTS "Service role can manage subscriptions" ON public.subscriptions;
CREATE POLICY "Service role can manage subscriptions"
  ON public.subscriptions FOR ALL USING (auth.role() = 'service_role');

-- ─── 3. AUDIT_LOG TABLE ─────────────────────────────────────
-- Reads: public (transparency)
-- Inserts: service_role only (keeper/system writes)
-- Note: table is named 'audit_log', not 'audit_logs'
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Audit logs are viewable by everyone" ON public.audit_log;
CREATE POLICY "Audit logs are viewable by everyone"
  ON public.audit_log FOR SELECT USING (true);

DROP POLICY IF EXISTS "Service role can insert audit logs" ON public.audit_log;
CREATE POLICY "Service role can insert audit logs"
  ON public.audit_log FOR INSERT WITH CHECK (auth.role() = 'service_role');

-- ─── 4. EPOCHS TABLE ────────────────────────────────────────
-- Reads: public
-- Inserts/Updates: service_role (keeper settles epochs)
ALTER TABLE public.epochs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Epochs are viewable by everyone" ON public.epochs;
CREATE POLICY "Epochs are viewable by everyone"
  ON public.epochs FOR SELECT USING (true);

DROP POLICY IF EXISTS "Service role can manage epochs" ON public.epochs;
CREATE POLICY "Service role can manage epochs"
  ON public.epochs FOR ALL USING (auth.role() = 'service_role');

-- ─── 5. VAULT_TRADING_ACCOUNTS TABLE ───────────────────────
-- Reads: public (which vault maps to which HL wallet is not secret)
-- Writes: service_role only
ALTER TABLE public.vault_trading_accounts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "vault_trading_accounts_read_all" ON public.vault_trading_accounts;
CREATE POLICY "vault_trading_accounts_read_all"
  ON public.vault_trading_accounts FOR SELECT USING (true);

DROP POLICY IF EXISTS "Service role can manage vault_trading_accounts" ON public.vault_trading_accounts;
CREATE POLICY "Service role can manage vault_trading_accounts"
  ON public.vault_trading_accounts FOR ALL USING (auth.role() = 'service_role');

-- ─── 6. EXECUTION_ATTEMPTS TABLE ───────────────────────────
-- Reads: public (audit trail)
-- Writes: service_role only
ALTER TABLE public.execution_attempts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "execution_attempts_read_all" ON public.execution_attempts;
CREATE POLICY "execution_attempts_read_all"
  ON public.execution_attempts FOR SELECT USING (true);

DROP POLICY IF EXISTS "Service role can manage execution_attempts" ON public.execution_attempts;
CREATE POLICY "Service role can manage execution_attempts"
  ON public.execution_attempts FOR ALL USING (auth.role() = 'service_role');

-- ─── 7. HL_USER_FILLS TABLE ────────────────────────────────
-- Reads: public (transparency)
-- Writes: service_role only
ALTER TABLE public.hl_user_fills ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "hl_user_fills_read_all" ON public.hl_user_fills;
CREATE POLICY "hl_user_fills_read_all"
  ON public.hl_user_fills FOR SELECT USING (true);

DROP POLICY IF EXISTS "Service role can manage hl_user_fills" ON public.hl_user_fills;
CREATE POLICY "Service role can manage hl_user_fills"
  ON public.hl_user_fills FOR ALL USING (auth.role() = 'service_role');

-- ─── 8. API_KEYS TABLE ─────────────────────────────────────
-- Reads: users can only see their own keys
-- Inserts: users can only create keys for themselves (provider = wallet address)
-- Deletes: users can only delete their own keys
-- Column is 'provider' (wallet address text), NOT 'user_id'
ALTER TABLE public.api_keys ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "api_keys_read_own" ON public.api_keys;
CREATE POLICY "api_keys_read_own"
  ON public.api_keys FOR SELECT USING (auth.uid()::text = provider);

DROP POLICY IF EXISTS "Users can insert own API keys" ON public.api_keys;
CREATE POLICY "Users can insert own API keys"
  ON public.api_keys FOR INSERT WITH CHECK (auth.uid()::text = provider);

DROP POLICY IF EXISTS "Users can delete own API keys" ON public.api_keys;
CREATE POLICY "Users can delete own API keys"
  ON public.api_keys FOR DELETE USING (auth.uid()::text = provider);

DROP POLICY IF EXISTS "Service role can manage api_keys" ON public.api_keys;
CREATE POLICY "Service role can manage api_keys"
  ON public.api_keys FOR ALL USING (auth.role() = 'service_role');

-- ─── 9. PROVIDER_STATS TABLE ───────────────────────────────
-- Reads: public (leaderboard)
-- Writes: service_role (keeper updates after epoch settlement)
ALTER TABLE public.provider_stats ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "provider_stats_read_all" ON public.provider_stats;
CREATE POLICY "provider_stats_read_all"
  ON public.provider_stats FOR SELECT USING (true);

DROP POLICY IF EXISTS "Service role can manage provider_stats" ON public.provider_stats;
CREATE POLICY "Service role can manage provider_stats"
  ON public.provider_stats FOR ALL USING (auth.role() = 'service_role');

-- ─── 10. SIGNAL_SCORES TABLE ───────────────────────────────
-- Reads: public (historical accuracy)
-- Writes: service_role only
ALTER TABLE public.signal_scores ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "signal_scores_read_all" ON public.signal_scores;
CREATE POLICY "signal_scores_read_all"
  ON public.signal_scores FOR SELECT USING (true);

DROP POLICY IF EXISTS "Service role can manage signal_scores" ON public.signal_scores;
CREATE POLICY "Service role can manage signal_scores"
  ON public.signal_scores FOR ALL USING (auth.role() = 'service_role');

-- ─── 11. EPOCH_HISTORY TABLE ────────────────────────────────
-- Reads: public
-- Writes: service_role only
ALTER TABLE public.epoch_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "epoch_history_read_all" ON public.epoch_history;
CREATE POLICY "epoch_history_read_all"
  ON public.epoch_history FOR SELECT USING (true);

DROP POLICY IF EXISTS "Service role can manage epoch_history" ON public.epoch_history;
CREATE POLICY "Service role can manage epoch_history"
  ON public.epoch_history FOR ALL USING (auth.role() = 'service_role');

-- ─── 12. PROVIDER_ANALYTICS TABLE ───────────────────────────
-- Reads: public
-- Writes: service_role only
ALTER TABLE public.provider_analytics ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "provider_analytics_read_all" ON public.provider_analytics;
CREATE POLICY "provider_analytics_read_all"
  ON public.provider_analytics FOR SELECT USING (true);

DROP POLICY IF EXISTS "Service role can manage provider_analytics" ON public.provider_analytics;
CREATE POLICY "Service role can manage provider_analytics"
  ON public.provider_analytics FOR ALL USING (auth.role() = 'service_role');

-- ─── 13. SUBSCRIPTION_EVENTS TABLE ─────────────────────────
-- Reads: public (Stripe event log for transparency)
-- Writes: service_role only (Stripe webhooks go through service role)
ALTER TABLE public.subscription_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "subscription_events_read_all" ON public.subscription_events;
CREATE POLICY "subscription_events_read_all"
  ON public.subscription_events FOR SELECT USING (true);

DROP POLICY IF EXISTS "Service role can manage subscription_events" ON public.subscription_events;
CREATE POLICY "Service role can manage subscription_events"
  ON public.subscription_events FOR ALL USING (auth.role() = 'service_role');

-- ─── 14. CROSS_CHAIN_SIGNAL_RECORDS TABLE ──────────────────
-- Reads: public
-- Writes: service_role only
ALTER TABLE public.cross_chain_signal_records ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "cross_chain_signal_records_read_all" ON public.cross_chain_signal_records;
CREATE POLICY "cross_chain_signal_records_read_all"
  ON public.cross_chain_signal_records FOR SELECT USING (true);

DROP POLICY IF EXISTS "Service role can manage cross_chain_signal_records" ON public.cross_chain_signal_records;
CREATE POLICY "Service role can manage cross_chain_signal_records"
  ON public.cross_chain_signal_records FOR ALL USING (auth.role() = 'service_role');

-- ─── 15. MARKET_STATS TABLE ────────────────────────────────
-- Reads: public
-- Writes: service_role only
ALTER TABLE public.market_stats ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "market_stats_read_all" ON public.market_stats;
CREATE POLICY "market_stats_read_all"
  ON public.market_stats FOR SELECT USING (true);

DROP POLICY IF EXISTS "Service role can manage market_stats" ON public.market_stats;
CREATE POLICY "Service role can manage market_stats"
  ON public.market_stats FOR ALL USING (auth.role() = 'service_role');

-- ─── 16. WEBHOOK_EVENTS TABLE ─────────────────────────────
-- Reads: service_role only (Stripe internal)
-- Writes: service_role only
ALTER TABLE public.webhook_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "webhook_events_insert_keeper" ON public.webhook_events;
DROP POLICY IF EXISTS "webhook_events_read_all" ON public.webhook_events;
CREATE POLICY "webhook_events_read_all"
  ON public.webhook_events FOR SELECT USING (auth.role() = 'service_role');
CREATE POLICY "webhook_events_insert_keeper"
  ON public.webhook_events FOR INSERT WITH CHECK (auth.role() = 'service_role');

-- ─── 17. VAULT_NAV_HISTORY TABLE ───────────────────────────
-- Reads: public (charts)
-- Writes: service_role only
ALTER TABLE public.vault_nav_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "vault_nav_history_read_all" ON public.vault_nav_history;
CREATE POLICY "vault_nav_history_read_all"
  ON public.vault_nav_history FOR SELECT USING (true);

DROP POLICY IF EXISTS "vault_nav_history_insert_service" ON public.vault_nav_history;
CREATE POLICY "vault_nav_history_insert_service"
  ON public.vault_nav_history FOR INSERT WITH CHECK (auth.role() = 'service_role');

DROP POLICY IF EXISTS "Service role can manage vault_nav_history" ON public.vault_nav_history;
CREATE POLICY "Service role can manage vault_nav_history"
  ON public.vault_nav_history FOR ALL USING (auth.role() = 'service_role');

-- ─── 18. VAULT_FLOW TABLE ─────────────────────────────────
-- Reads: public
-- Writes: service_role only
ALTER TABLE public.vault_flow ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "vault_flow_read_all" ON public.vault_flow;
CREATE POLICY "vault_flow_read_all"
  ON public.vault_flow FOR SELECT USING (true);

DROP POLICY IF EXISTS "vault_flow_insert_service" ON public.vault_flow;
CREATE POLICY "vault_flow_insert_service"
  ON public.vault_flow FOR INSERT WITH CHECK (auth.role() = 'service_role');

DROP POLICY IF EXISTS "Service role can manage vault_flow" ON public.vault_flow;
CREATE POLICY "Service role can manage vault_flow"
  ON public.vault_flow FOR ALL USING (auth.role() = 'service_role');

-- ─── 19. VAULT_PERFORMANCE TABLE ───────────────────────────
-- Reads: public
-- Writes: service_role only
ALTER TABLE public.vault_performance ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "vault_performance_read_all" ON public.vault_performance;
CREATE POLICY "vault_performance_read_all"
  ON public.vault_performance FOR SELECT USING (true);

DROP POLICY IF EXISTS "vault_performance_insert_service" ON public.vault_performance;
CREATE POLICY "vault_performance_insert_service"
  ON public.vault_performance FOR INSERT WITH CHECK (auth.role() = 'service_role');

DROP POLICY IF EXISTS "Service role can manage vault_performance" ON public.vault_performance;
CREATE POLICY "Service role can manage vault_performance"
  ON public.vault_performance FOR ALL USING (auth.role() = 'service_role');

-- ─── 20. WHITELIST TABLE ───────────────────────────────────
-- Reads: public (anyone can check if their email is on the list)
-- Writes: service_role only (managed by admin)
ALTER TABLE public.whitelist ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "whitelist_insert_public" ON public.whitelist;
CREATE POLICY "whitelist_insert_public"
  ON public.whitelist FOR INSERT WITH CHECK (auth.role() = 'service_role');

DROP POLICY IF EXISTS "whitelist_read_admin" ON public.whitelist;
CREATE POLICY "whitelist_read_admin"
  ON public.whitelist FOR SELECT USING (true);

DROP POLICY IF EXISTS "Service role can manage whitelist" ON public.whitelist;
CREATE POLICY "Service role can manage whitelist"
  ON public.whitelist FOR ALL USING (auth.role() = 'service_role');

-- ============================================================
-- VERIFICATION
-- ============================================================
SELECT
  schemaname,
  tablename,
  rowsecurity
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename IN (
    'signals','subscriptions','audit_log','epochs',
    'vault_trading_accounts','execution_attempts','hl_user_fills',
    'api_keys','provider_stats','signal_scores','epoch_history',
    'provider_analytics','subscription_events','cross_chain_signal_records',
    'market_stats','webhook_events','vault_nav_history','vault_flow',
    'vault_performance','whitelist'
  )
ORDER BY tablename;
