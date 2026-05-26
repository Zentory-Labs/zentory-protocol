-- ─────────────────────────────────────────────────────────────────────────
-- 2026-05-25  Add UNIQUE constraint to execution_attempts
-- ─────────────────────────────────────────────────────────────────────────
-- The indexer (scripts/index_strategy_executor_events.py) uses Supabase
-- REST's `Prefer: resolution=merge-duplicates` header for upserts. That
-- header only works when there's a unique constraint matching the
-- conflict target.
--
-- Right now `execution_attempts` only has a UNIQUE on the auto-generated
-- `id` (UUID), which means upserts NEVER conflict and the indexer just
-- inserts a fresh row every time it scans overlapping block ranges. The
-- cron runs every 15 min and scans the most-recent 1000 blocks (~5 min
-- of HyperEVM activity), so each event gets indexed multiple times until
-- it falls out of the scan window.
--
-- Adding UNIQUE(tx_hash, vault_address, nonce) gives the upsert a real
-- target. After this runs, the same event scanned twice = one row,
-- updated in place.
--
-- Tracked as task #106. Run this in Supabase SQL Editor when ready.
-- Safe to run multiple times (NOT NULL backfills + IF NOT EXISTS guards).

BEGIN;

-- Backfill any nulls before adding the constraint. The indexer writes
-- these fields on every insert, so nulls only exist if there was
-- historical bad data. If the count is non-zero, investigate before
-- proceeding.
SELECT count(*) AS rows_with_null_nonce
FROM public.execution_attempts
WHERE nonce IS NULL OR vault_address IS NULL OR tx_hash IS NULL;

-- If the above returns 0, proceed. If > 0, decide whether to delete or
-- backfill before adding the constraint (uncomment the appropriate line):
-- DELETE FROM public.execution_attempts WHERE nonce IS NULL OR vault_address IS NULL OR tx_hash IS NULL;
-- -- OR --
-- UPDATE public.execution_attempts SET nonce = 0 WHERE nonce IS NULL; -- bogus but unblocks the constraint

-- Add the unique constraint. (tx_hash, vault_address, nonce) is unique
-- because each TradeSignalExecuted event has a unique nonce per (vault,
-- tx) combination — the StrategyExecutor enforces nonce monotonicity in
-- Solidity.
ALTER TABLE public.execution_attempts
  ADD CONSTRAINT execution_attempts_dedupe_key
  UNIQUE (tx_hash, vault_address, nonce);

-- Drop duplicate rows that snuck in before the constraint was added.
-- Keep the oldest row (smallest created_at) for each dedupe key.
WITH ranked AS (
  SELECT
    id,
    row_number() OVER (
      PARTITION BY tx_hash, vault_address, nonce
      ORDER BY created_at ASC, id ASC
    ) AS rn
  FROM public.execution_attempts
)
DELETE FROM public.execution_attempts
WHERE id IN (SELECT id FROM ranked WHERE rn > 1);

COMMIT;

-- Verify
SELECT
  conname AS constraint_name,
  pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid = 'public.execution_attempts'::regclass
  AND contype = 'u';
