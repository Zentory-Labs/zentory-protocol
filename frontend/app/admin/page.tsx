"use client";

import { useAccount, useReadContract, useWriteContract } from "wagmi";
import { EXECUTOR_ABI, VAULT_ABI, addresses, vaultMeta } from "@/lib/contracts";
import { useState } from "react";

const VAULTS = [addresses.zETH, addresses.zBTC, addresses.zXRP, addresses.zSOL] as const;

function shorten(addr: string): string {
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}

function fmtBPS(raw: bigint): string {
  return `${(Number(raw) / 100).toFixed(1)}%`;
}

export default function AdminPage() {
  const { address, isConnected } = useAccount();
  const { writeContract } = useWriteContract();

  const isPaused = useReadContract({
    address: addresses.StrategyExecutor,
    abi: EXECUTOR_ABI,
    functionName: "paused",
  } as any);

  const keeperRole = useReadContract({
    address: addresses.StrategyExecutor,
    abi: EXECUTOR_ABI,
    functionName: "KEEPER_ROLE",
  } as any);

  const guardianRole = useReadContract({
    address: addresses.StrategyExecutor,
    abi: EXECUTOR_ABI,
    functionName: "GUARDIAN_ROLE",
  } as any);

  const [selectedVault, setSelectedVault] = useState<string>(addresses.zETH);
  const [maxPosSize, setMaxPosSize] = useState("");
  const [maxLevBPS, setMaxLevBPS] = useState("");
  const [txStatus, setTxStatus] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const meta = vaultMeta[selectedVault];

  const vaultMaxPos = useReadContract({
    address: addresses.StrategyExecutor,
    abi: EXECUTOR_ABI,
    functionName: "maxPositionSize",
    args: [selectedVault],
  } as any);

  const vaultMaxLev = useReadContract({
    address: addresses.StrategyExecutor,
    abi: EXECUTOR_ABI,
    functionName: "maxLeverageBPS",
    args: [selectedVault],
  } as any);

  function handlePauseToggle() {
    const shouldPause = !(isPaused.data as boolean);
    try {
      writeContract({
        address: addresses.StrategyExecutor,
        abi: EXECUTOR_ABI,
        functionName: "setPaused",
        args: [shouldPause],
      } as any);
      setTxStatus(shouldPause ? "Pausing executor…" : "Resuming executor…");
    } catch (err: any) {
      setError(err.message);
    }
  }

  function handleSetMaxPos() {
    if (!maxPosSize) return;
    try {
      writeContract({
        address: addresses.StrategyExecutor,
        abi: EXECUTOR_ABI,
        functionName: "setMaxPositionSize",
        args: [selectedVault, BigInt(parseFloat(maxPosSize) * 1e18)],
      } as any);
      setTxStatus("Setting max position size…");
      setMaxPosSize("");
    } catch (err: any) {
      setError(err.message);
    }
  }

  function handleSetMaxLev() {
    if (!maxLevBPS) return;
    const bps = BigInt(Math.round(parseFloat(maxLevBPS) * 100));
    try {
      writeContract({
        address: addresses.StrategyExecutor,
        abi: EXECUTOR_ABI,
        functionName: "setMaxLeverageBPS",
        args: [selectedVault, bps],
      } as any);
      setTxStatus("Setting max leverage…");
      setMaxLevBPS("");
    } catch (err: any) {
      setError(err.message);
    }
  }

  return (
    <div className="min-h-screen">
      <header className="border-b border-white/10 bg-[#0d0d14]/80 backdrop-blur-sm sticky top-0 z-10">
        <div className="mx-auto max-w-7xl px-6 py-4">
          <div className="flex items-center gap-3">
            <h1 className="text-2xl font-bold text-white">Admin & Keeper</h1>
            <span className="text-xs bg-red-950 border border-red-800 text-red-400 rounded-full px-2 py-0.5">
              Role-gated
            </span>
          </div>
          <p className="text-xs text-white/40 mt-0.5">Manage risk parameters, emergency pause, and keeper configuration</p>
        </div>
      </header>

      <main className="mx-auto max-w-4xl px-6 py-10 space-y-8">
        {/* Executor Status */}
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <div className="rounded-2xl border border-white/10 bg-white/5 p-5">
            <div className="text-xs text-white/40 mb-1 uppercase tracking-wider">Executor Status</div>
            <div className={`text-2xl font-bold ${(isPaused.data as boolean) ? "text-red-400" : "text-emerald-400"}`}>
              {(isPaused.data as boolean) ? "PAUSED" : "Active"}
            </div>
          </div>
          <div className="rounded-2xl border border-white/10 bg-white/5 p-5">
            <div className="text-xs text-white/40 mb-1 uppercase tracking-wider">Keeper Role Hash</div>
            <div className="font-mono text-xs text-white break-all leading-tight">
              {keeperRole.data ? (keeperRole.data as string).slice(0, 16) + "…" : "—"}
            </div>
          </div>
          <div className="rounded-2xl border border-white/10 bg-white/5 p-5">
            <div className="text-xs text-white/40 mb-1 uppercase tracking-wider">Guardian Role Hash</div>
            <div className="font-mono text-xs text-white break-all leading-tight">
              {guardianRole.data ? (guardianRole.data as string).slice(0, 16) + "…" : "—"}
            </div>
          </div>
        </div>

        {/* Emergency Pause */}
        <div className="rounded-2xl border border-red-500/20 bg-red-500/5 p-6">
          <h2 className="text-lg font-semibold text-red-400 mb-1">Emergency Pause</h2>
          <p className="text-xs text-white/40 mb-4">
            Immediately halts all trade execution. Guardian role required.
          </p>
          <button
            onClick={handlePauseToggle}
            className={`rounded-lg px-6 py-2.5 font-bold transition-colors ${
              (isPaused.data as boolean)
                ? "bg-emerald-600 hover:bg-emerald-500 text-white"
                : "bg-red-700 hover:bg-red-600 text-white"
            }`}
          >
            {(isPaused.data as boolean) ? "Resume Executor" : "Pause Executor"}
          </button>
        </div>

        {/* Vault Risk Parameters */}
        <div className="rounded-2xl border border-white/10 bg-white/5 p-6">
          <h2 className="text-lg font-semibold text-white mb-4">Vault Risk Parameters</h2>

          {/* Vault Selector */}
          <div className="mb-5">
            <label className="mb-2 block text-xs font-medium text-white/60 uppercase tracking-wider">Select Vault</label>
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
              {VAULTS.map((v) => {
                const m = vaultMeta[v];
                return (
                  <button
                    key={v}
                    onClick={() => setSelectedVault(v)}
                    className={`rounded-lg border py-2 px-3 text-sm font-medium transition-colors ${
                      selectedVault === v
                        ? "border-amber-500 bg-amber-950/40 text-amber-400"
                        : "border-white/10 bg-white/5 text-white/60 hover:border-white/30"
                    }`}
                  >
                    {m.symbol}
                  </button>
                );
              })}
            </div>
          </div>

          {/* Current values */}
          <div className="grid grid-cols-2 gap-4 mb-5 p-4 rounded-lg bg-white/5 border border-white/10">
            <div>
              <div className="text-xs text-white/40 mb-1">Max Position Size ({meta.symbol})</div>
              <div className="font-mono font-semibold text-white">
                {vaultMaxPos.data !== undefined ? `${(Number(vaultMaxPos.data as bigint) / 1e18).toFixed(4)}` : "—"}
              </div>
            </div>
            <div>
              <div className="text-xs text-white/40 mb-1">Max Leverage</div>
              <div className="font-mono font-semibold text-white">
                {vaultMaxLev.data !== undefined ? fmtBPS(vaultMaxLev.data as bigint) : "—"}
              </div>
            </div>
          </div>

          {/* Set forms */}
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div>
              <label className="mb-1.5 block text-xs font-medium text-white/60">Max Position Size (asset units)</label>
              <div className="flex gap-2">
                <input
                  type="number"
                  step="any"
                  min="0"
                  placeholder="e.g. 10.0"
                  value={maxPosSize}
                  onChange={(e) => setMaxPosSize(e.target.value)}
                  className="flex-1 rounded-lg border border-slate-700 bg-slate-900 px-3 py-2 font-mono text-white text-sm outline-none focus:border-amber-500"
                />
                <button
                  onClick={handleSetMaxPos}
                  disabled={!maxPosSize}
                  className="rounded-lg bg-amber-600 hover:bg-amber-500 disabled:opacity-50 text-white font-semibold px-4 py-2 text-sm transition-colors"
                >
                  Set
                </button>
              </div>
            </div>
            <div>
              <label className="mb-1.5 block text-xs font-medium text-white/60">Max Leverage (% or bps)</label>
              <div className="flex gap-2">
                <input
                  type="number"
                  step="any"
                  min="0"
                  placeholder="e.g. 300 (= 3x)"
                  value={maxLevBPS}
                  onChange={(e) => setMaxLevBPS(e.target.value)}
                  className="flex-1 rounded-lg border border-slate-700 bg-slate-900 px-3 py-2 font-mono text-white text-sm outline-none focus:border-amber-500"
                />
                <button
                  onClick={handleSetMaxLev}
                  disabled={!maxLevBPS}
                  className="rounded-lg bg-amber-600 hover:bg-amber-500 disabled:opacity-50 text-white font-semibold px-4 py-2 text-sm transition-colors"
                >
                  Set
                </button>
              </div>
            </div>
          </div>
        </div>

        {/* Status */}
        {(txStatus || error) && (
          <div className={`rounded-lg border px-4 py-3 text-sm ${error ? "border-red-800 bg-red-950/50 text-red-400" : "border-amber-800 bg-amber-950/50 text-amber-400"}`}>
            {error ?? txStatus}
          </div>
        )}

        {/* Keeper Info */}
        <div className="rounded-2xl border border-white/10 bg-white/5 p-5">
          <h2 className="text-lg font-semibold text-white mb-4">Contract Addresses</h2>
          <div className="space-y-2">
            {[
              { label: "StrategyExecutor", addr: addresses.StrategyExecutor },
              { label: "HyperCoreAdapter", addr: addresses.HyperCoreAdapter },
            ].map(({ label, addr }) => (
              <div key={label} className="flex justify-between items-center text-sm">
                <span className="text-white/50">{label}</span>
                <a
                  href={`https://hypurrscan.io/address/${addr}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="font-mono text-xs text-blue-400 hover:text-blue-300"
                >
                  {shorten(addr)} →
                </a>
              </div>
            ))}
          </div>
        </div>
      </main>
    </div>
  );
}
