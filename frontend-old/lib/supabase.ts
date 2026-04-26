import { createClient } from "@/utils/supabase/client";
import type { Asset, Direction, SignalProvider } from "@/lib/signals";

// ─── Database types ─────────────────────────────────────────────────────────────

export interface DbSignal {
  id: string;
  created_at: string;
  provider: SignalProvider;
  asset: Asset;
  direction: Direction;
  size: number;
  price: number;
  status: "pending" | "executed" | "failed";
  tx_hash: string | null;
  executed_by: string | null;
  executor_address: string | null;
}

export interface DbKeeperAudit {
  id: string;
  signal_id: string | null;
  tx_hash: string;
  gas_used: number | null;
  executor_address: string | null;
  block_number: number | null;
  created_at: string;
}

// ─── Signal helpers (browser/client-side) ──────────────────────────────────────

/** Fetch signals from Supabase */
export async function getSignals(limit = 100) {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("signals")
    .select("*")
    .order("created_at", { ascending: false })
    .limit(limit);
  if (error) {
    console.error("[supabase] getSignals:", error.message);
    return [];
  }
  return (data as DbSignal[]) ?? [];
}

/** Insert a new signal */
export async function insertSignal(
  signal: Omit<DbSignal, "id" | "created_at">
) {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("signals")
    .insert(signal)
    .select()
    .single();
  if (error) {
    console.error("[supabase] insertSignal:", error.message);
    return null;
  }
  return data as DbSignal;
}

/** Update signal status after execution */
export async function updateSignalStatus(
  id: string,
  status: "pending" | "executed" | "failed",
  txHash?: string,
  executedBy?: string,
  executorAddress?: string
) {
  const supabase = createClient();
  const { error } = await supabase
    .from("signals")
    .update({
      status,
      tx_hash: txHash ?? null,
      executed_by: executedBy ?? null,
      executor_address: executorAddress ?? null,
    })
    .eq("id", id);
  if (error) console.error("[supabase] updateSignalStatus:", error.message);
}

// ─── Keeper audit helpers ──────────────────────────────────────────────────────

export async function insertKeeperAudit(
  entry: Omit<DbKeeperAudit, "id" | "created_at">
) {
  const supabase = createClient();
  const { error } = await supabase.from("keeper_audit").insert(entry);
  if (error) console.error("[supabase] insertKeeperAudit:", error.message);
}

export async function getKeeperAudit(limit = 50) {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("keeper_audit")
    .select("*")
    .order("created_at", { ascending: false })
    .limit(limit);
  if (error) {
    console.error("[supabase] getKeeperAudit:", error.message);
    return [];
  }
  return (data as DbKeeperAudit[]) ?? [];
}
