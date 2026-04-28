export interface Signal {
  id: string;
  provider: string;
  assetClass: string;
  assetId: string;
  direction: number; // -10000 to 10000
  confidence: number;
  expiresAt: number;
  submittedAt: number;
  status: 'Active' | 'Resolved';
}

export interface AccuracyResult {
  signalId: string;
  accuracyBps: number; // 0 to 10000
  priceChangeBps: number;
}

export interface PayoutResult {
  signalId: string;
  provider: string;
  payoutZent: bigint;
  success: boolean;
  error?: string;
}

export interface EpochHistoryRecord {
  epoch_id: number;
  start_time: number;
  end_time: number;
  total_signals: number;
  settled_signals: number;
  avg_accuracy_bps: number;
}

export interface ProviderStatsRecord {
  provider: string;
  epoch_id: number;
  accuracy_bps: number;
  payout_zent: string;
}

export interface SignalScoreRecord {
  signal_id: string;
  epoch_id: number;
  accuracy_bps: number;
  payout_zent: string;
}

export interface AuditLogRecord {
  actor: string;
  action: string;
  payload: Record<string, unknown>;
  timestamp?: number;
}
