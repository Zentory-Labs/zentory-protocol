export type Direction = "LONG" | "SHORT" | "CLOSE";
export type SignalStatus = "pending" | "executed" | "failed";
export type SignalProvider = "gp" | "lumibot" | "manual";
export type Asset = "BTC" | "ETH" | "XRP" | "SOL";

export interface Signal {
  id: string;
  timestamp: number;
  provider: SignalProvider;
  asset: Asset;
  direction: Direction;
  size: number;
  price: number;
  status: SignalStatus;
  txHash?: string;
}

export interface SignalInput {
  asset: Asset;
  direction: Direction;
  size: number;
  price: number;
}

export async function getSignals(): Promise<Signal[]> {
  const res = await fetch("/api/signals", { cache: "no-store" });
  if (!res.ok) throw new Error("Failed to fetch signals");
  return res.json();
}

export async function logSignal(data: SignalInput): Promise<Signal> {
  const res = await fetch("/api/signals", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(data),
  });
  if (!res.ok) throw new Error("Failed to log signal");
  return res.json();
}

export async function executeSignal(signal: Signal): Promise<{ txHash: string }> {
  const res = await fetch("/api/signals/execute", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(signal),
  });
  if (!res.ok) throw new Error("Failed to execute signal");
  return res.json();
}
