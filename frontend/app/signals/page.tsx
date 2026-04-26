"use client";

import { useEffect, useState, useCallback } from "react";
import { useAccount } from "wagmi";
import { getSignals } from "@/lib/signals";
import type { Signal } from "@/lib/signals";
import SignalTable from "@/components/SignalTable";
import TradeLoggerForm from "./TradeLoggerForm";

export default function SignalsPage() {
  const { address, isConnected } = useAccount();
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
    <div className="min-h-screen relative" style={{ background: "#0b0b0d" }}>
      {/* Ambient glows */}
      <div className="absolute top-0 left-1/4 w-96 h-96 bg-[#8b1e2d]/5 rounded-full blur-3xl pointer-events-none -z-10" />
      <div className="absolute bottom-0 right-1/4 w-96 h-96 bg-[#b08d57]/5 rounded-full blur-3xl pointer-events-none -z-10" />

      <main className="mx-auto max-w-7xl px-6 py-10 space-y-8">
        {/* Header */}
        <div className="glass-card p-6 flex items-center justify-between">
          <div>
            <div
              className="inline-flex items-center gap-2 rounded-full border px-3 py-1 text-xs font-medium mb-2"
              style={{
                background: "rgba(139, 30, 45, 0.15)",
                borderColor: "rgba(139, 30, 45, 0.4)",
                color: "#c2353f",
                fontFamily: "'Montserrat', sans-serif",
              }}
            >
              <div className="h-1.5 w-1.5 rounded-full animate-pulse" style={{ background: "#c2353f", boxShadow: "0 0 8px #c2353f" }} />
              LIVE
            </div>
            <h1 className="text-3xl font-bold tracking-tight" style={{ fontFamily: "'Montserrat', sans-serif" }}>
              <span className="gradient-text-gold">Signal Dashboard</span>
            </h1>
            <p className="mt-1 text-sm text-white/40">
              Auto-refreshes every 30s · stored on-chain via StrategyExecutor
            </p>
          </div>
          {isConnected && address && (
            <div className="rounded-2xl border border-white/[0.1] bg-black/60 backdrop-blur-xl px-4 py-2">
              <span className="font-mono text-xs text-white/60">Keeper: </span>
              <span className="font-mono text-xs" style={{ color: "#b08d57" }}>{address.slice(0, 6)}…{address.slice(-4)}</span>
            </div>
          )}
        </div>

        {error && (
          <div className="rounded-2xl border border-red-500/20 bg-red-500/5 glass-card px-4 py-3 text-sm text-red-400 backdrop-blur-sm">
            {error}
          </div>
        )}

        {/* Signal table — public */}
        <section>
          {loading ? (
            <div className="flex items-center justify-center py-24">
              <div className="h-8 w-8 rounded-full border-2 border-amber-500 border-t-transparent animate-spin" />
            </div>
          ) : (
            <div className="glass-card overflow-hidden">
              <SignalTable signals={signals} />
            </div>
          )}
        </section>

        {/* Trade form — keeper only */}
        {isConnected ? (
          <div className="glass-card p-6" style={{ borderColor: "rgba(139, 30, 45, 0.3)" }}>
            <TradeLoggerForm />
          </div>
        ) : (
          <div className="rounded-2xl border border-white/[0.1] bg-black/60 backdrop-blur-xl p-8 text-center">
            <div className="mb-4 flex justify-center">
              <div
                className="h-12 w-12 rounded-full flex items-center justify-center border"
                style={{ background: "rgba(139, 30, 45, 0.12)", borderColor: "rgba(139, 30, 45, 0.25)" }}
              >
                <svg
                  className="h-6 w-6"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                  style={{ color: "#c2353f" }}
                >
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
                </svg>
              </div>
            </div>
            <h3 className="text-lg font-semibold text-white mb-2">Keeper Access Required</h3>
            <p className="text-sm text-white/50 max-w-sm mx-auto">
              Connect your wallet to log signals and execute trades on-chain.
              Only the keeper wallet can execute transactions.
            </p>
          </div>
        )}
      </main>
    </div>
  );
}
