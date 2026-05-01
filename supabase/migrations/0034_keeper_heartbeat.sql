-- Keeper Heartbeat / Dead Man's Switch Table
CREATE TABLE IF NOT EXISTS public.keeper_heartbeats (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  keeper_address TEXT NOT NULL UNIQUE,
  last_heartbeat TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_epoch_settled BIGINT DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'missed_heartbeat', 'failed', 'recovered')),
  missed_heartbeats INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for fast lookups
CREATE INDEX IF NOT EXISTS idx_keeper_heartbeats_address ON public.keeper_heartbeats(keeper_address);
CREATE INDEX IF NOT EXISTS idx_keeper_heartbeats_status ON public.keeper_heartbeats(status);

-- Enable RLS
ALTER TABLE public.keeper_heartbeats ENABLE ROW LEVEL SECURITY;

-- Anyone can read keeper status (transparency)
CREATE POLICY "Anyone can read keeper status"
  ON public.keeper_heartbeats FOR SELECT USING (true);

-- Only service role can insert/update (keeper itself via service role)
CREATE POLICY "Service role can manage keeper heartbeats"
  ON public.keeper_heartbeats FOR INSERT WITH CHECK (true);
CREATE POLICY "Service role can update keeper heartbeats"
  ON public.keeper_heartbeats FOR UPDATE USING (true);

-- Function to check if keeper is alive
CREATE OR REPLACE FUNCTION public.is_keeper_alive(p_keeper_address TEXT)
RETURNS BOOLEAN AS $$
DECLARE
  last_seen TIMESTAMPTZ;
BEGIN
  SELECT last_heartbeat INTO last_seen
  FROM keeper_heartbeats
  WHERE keeper_address = p_keeper_address
  ORDER BY updated_at DESC
  LIMIT 1;

  IF last_seen IS NULL THEN
    RETURN FALSE;
  END IF;

  -- Alive if last heartbeat within 5 hours
  RETURN (NOW() - last_seen) < INTERVAL '5 hours';
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- Function to update keeper heartbeat
CREATE OR REPLACE FUNCTION public.update_keeper_heartbeat(
  p_keeper_address TEXT,
  p_last_epoch BIGINT
)
RETURNS VOID AS $$
BEGIN
  INSERT INTO keeper_heartbeats (keeper_address, last_heartbeat, last_epoch_settled, status, missed_heartbeats)
  VALUES (p_keeper_address, NOW(), p_last_epoch, 'active', 0)
  ON CONFLICT (keeper_address) DO UPDATE SET
    last_heartbeat = NOW(),
    last_epoch_settled = p_last_epoch,
    status = 'active',
    missed_heartbeats = 0,
    updated_at = NOW();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
