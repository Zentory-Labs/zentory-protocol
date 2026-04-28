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
  const { data, error } = await supabase
    .from('signals')
    .select('*')
    .eq('status', 'Active')
    .gte('submitted_at', startTime.toString())
    .lt('submitted_at', endTime.toString());

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
    .order('submitted_at', { ascending: true })
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
