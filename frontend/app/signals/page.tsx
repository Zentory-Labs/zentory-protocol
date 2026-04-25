"use client";

import { useEffect, useState, useCallback } from "react";
import { getSignals } from "@/lib/signals";
import type { Signal } from "@/lib/signals";
import SignalTable from "@/components/SignalTable";
import TradeLoggerForm from "./TradeLoggerForm";

export default function SignalsPage() {
  const [signals, setSignals] = useState<Signal[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchSignals = useCallback(async () => {
    try {
      const data = await getSignals();
      setSignals(data);
      setError(null);
    } catch {
      setError("Failed to load signals.");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchSignals();
    const interval = setInterval(fetchSignals, 30_000);
    return () => clearInterval(interval);
  }, [fetchSignals]);

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100">
      <header className="border-b border-slate-800 bg-slate-900/80 backdrop-blur-sm sticky top-0 z-10">
        <div className="mx-auto max-w-7xl px-6 py-4">
          <div className="flex items-center justify-between">
            <div>
              <h1 className="text-2xl font-bold tracking-tight text-white">Signal Dashboard</h1>
              <p className="mt-0.5 text-xs text-slate-500">
                Real-time signal feed · auto-refreshes every 30s
              </p>
            </div>
            <div className="flex items-center gap-2">
              <span className="h-2 w-2 rounded-full bg-emerald-500 animate-pulse" />
              <span className="text-xs text-slate-500 font-mono">LIVE</span>
            </div>
          </div>
        </div>
      </header>

      <main className="mx-auto max-w-7xl px-6 py-8 space-y-8">
        {error && (
          <div className="rounded-lg border border-red-800 bg-red-950/50 px-4 py-3 text-sm text-red-400">
            {error}
          </div>
        )}

        <section>
          <SignalTable signals={signals} />
        </section>

        <section>
          <TradeLoggerForm />
        </section>
      </main>
    </div>
  );
}
