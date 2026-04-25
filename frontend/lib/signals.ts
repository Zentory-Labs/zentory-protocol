export type Direction = "LONG" | "SHORT" | "CLOSE";
export type SignalStatus = "pending" | "executed" | "failed";
export type SignalProvider = "gp" | "lumibot" | "manual";
export type Asset = "BTC" | "ETH" | "XRP" | "SOL";

export interface Signal {
  id: string;
  created_at?: string;
  timestamp?: number;
  provider: SignalProvider;
  asset: Asset;
  direction: Direction;
  size: number;
  price: number;
  status: SignalStatus;
  txHash?: string;
}

export interface SignalInput {
  provider: SignalProvider;
  asset: Asset;
  direction: Direction;
  size: number;
  price: number;
}

export async function getSignals(): Promise<Signal[]> {
  const res = await fetch("/api/signals", { cache: "no-store" });
  if (!res.ok) throw new Error("Failed to fetch signals");
  const data = await res.json();
  return data.map((s: Record<string, unknown>) => ({
    ...s,
    txHash: s.tx_hash as string | undefined,
    timestamp: s.created_at ? new Date(s.created_at as string).getTime() : 0,
  }));
}

/**
 * POST a signal to Supabase via the protected /api/signals/log route.
 * The KEEPER_API_KEY is injected by Vercel and never exposed to the browser.
 */
export async function logSignal(data: SignalInput): Promise<Signal> {
  const res = await fetch("/api/signals/log", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(data),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({ error: "Unknown error" }));
    throw new Error(err.error ?? "Failed to log signal");
  }
  return res.json();
}

/**
 * Execute a signal on-chain via the keeper route.
 * KEEPER_PRIVATE_KEY is server-side only — this call goes through Next.js API.
 */
export async function executeSignal(
  signal: Signal & { signalId?: string }
): Promise<{ txHash: string; blockNumber?: number }> {
  const res = await fetch("/api/signals/execute", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      signalId: signal.signalId ?? signal.id,
      asset: signal.asset,
      direction: signal.direction,
      size: signal.size,
      price: signal.price,
    }),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({ error: "Execution failed" }));
    throw new Error(err.error ?? "Execution failed");
  }
  return res.json();
}
