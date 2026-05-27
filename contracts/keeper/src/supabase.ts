import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { config } from './config';
import {
  Signal,
  EpochHistoryRecord,
  ProviderStatsRecord,
  SignalScoreRecord,
  AuditLogRecord,
} from './types';

export const supabase: SupabaseClient = createClient(
  config.supabase.url,
  config.supabase.serviceRoleKey
);

export async function getActiveSignalsForEpoch(
  startTime: number,
  endTime: number
): Promise<Signal[]> {
  // The signals table has no `submitted_at` column — the submission time is
  // `created_at` (timestamptz). The previous query referenced a non-existent
  // column AND compared a timestamptz against raw unix-second strings, so the
  // keeper crashed on every run ("column signals.submitted_at does not exist")
  // and never reached settleEpoch — leaving the epoch loop stalled. Convert
  // the unix-second epoch bounds to ISO timestamps for the timestamptz column.
  const startIso = new Date(startTime * 1000).toISOString();
  const endIso = new Date(endTime * 1000).toISOString();

  const { data, error } = await supabase
    .from('signals')
    .select('*')
    .eq('status', 'Active')
    .gte('created_at', startIso)
    .lt('created_at', endIso);

  if (error) {
    throw new Error(`Failed to fetch signals: ${error.message}`);
  }

  return (data ?? []) as unknown as Signal[];
}

export async function getAssetPriceOnDate(
  assetId: string,
  timestamp: number
): Promise<number> {
  const { data, error } = await supabase
    .from('price_data')
    .select('price_usd')
    .eq('asset_id', assetId)
    .lte('timestamp', timestamp.toString())
    .order('timestamp', { ascending: false })
    .limit(1);

  if (error) {
    throw new Error(`Failed to fetch price: ${error.message}`);
  }

  if (!data || data.length === 0) {
    throw new Error(`No price data found for asset ${assetId} at timestamp ${timestamp}`);
  }

  return parseFloat(data[0].price_usd);
}

export async function insertEpochHistory(epochData: EpochHistoryRecord): Promise<void> {
  const { error } = await supabase.from('epoch_history').insert([epochData]);

  if (error) {
    throw new Error(`Failed to insert epoch history: ${error.message}`);
  }
}

export async function updateProviderStats(
  provider: string,
  epochId: number,
  accuracy: number,
  payout: bigint
): Promise<void> {
  const record: ProviderStatsRecord = {
    provider,
    epoch_id: epochId,
    accuracy_bps: accuracy,
    payout_zent: payout.toString(),
  };

  const { error } = await supabase.from('provider_stats').insert([record]);

  if (error) {
    throw new Error(`Failed to update provider stats: ${error.message}`);
  }
}

export async function insertSignalScore(
  signalId: string,
  epochId: number,
  accuracyBps: number,
  payoutZent: string
): Promise<void> {
  const record: SignalScoreRecord = {
    signal_id: signalId,
    epoch_id: epochId,
    accuracy_bps: accuracyBps,
    payout_zent: payoutZent,
  };

  const { error } = await supabase.from('signal_scores').insert([record]);

  if (error) {
    throw new Error(`Failed to insert signal score: ${error.message}`);
  }
}

export async function insertAuditLog(
  actor: string,
  action: string,
  payload: Record<string, unknown>
): Promise<void> {
  const record: AuditLogRecord = {
    actor,
    action,
    payload,
    timestamp: Math.floor(Date.now() / 1000),
  };

  const { error } = await supabase.from('audit_logs').insert([record]);

  if (error) {
    console.error(`Failed to insert audit log: ${error.message}`);
  }
}

export async function getUnsettledSignals(limit = 100): Promise<Signal[]> {
  const { data, error } = await supabase
    .from('signals')
    .select('*')
    .eq('status', 'Active')
    .order('created_at', { ascending: true }) // no submitted_at column — see getActiveSignalsForEpoch
    .limit(limit);

  if (error) {
    throw new Error(`Failed to fetch unsettled signals: ${error.message}`);
  }

  return (data ?? []) as unknown as Signal[];
}

export async function markSignalsAsResolved(signalIds: string[]): Promise<void> {
  const { error } = await supabase
    .from('signals')
    .update({ status: 'Resolved' })
    .in('id', signalIds);

  if (error) {
    throw new Error(`Failed to mark signals as resolved: ${error.message}`);
  }
}

export async function updateKeeperHeartbeat(epochId: number): Promise<void> {
  const { error } = await supabase.rpc('update_keeper_heartbeat', {
    p_keeper_address: config.keeperAddress,
    p_last_epoch: epochId,
  });

  if (error) {
    console.error(`Failed to update keeper heartbeat: ${error.message}`);
  }
}
