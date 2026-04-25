"use client";

import type { Signal } from "@/lib/signals";

const EXPLORER_BASE = "https://evm.l2scan.co/tx";

function formatTimestamp(ts: number): string {
  return new Date(ts).toLocaleString("en-US", {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  });
}

function DirectionBadge({ direction }: { direction: Signal["direction"] }) {
  const classes =
    direction === "LONG"
      ? "bg-emerald-900/60 text-emerald-400 border border-emerald-700"
      : direction === "SHORT"
      ? "bg-red-900/60 text-red-400 border border-red-700"
      : "bg-slate-700/60 text-slate-300 border border-slate-600";
  return (
    <span
      className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-mono font-semibold uppercase tracking-wider ${classes}`}
    >
      {direction}
    </span>
  );
}

function StatusBadge({ status }: { status: Signal["status"] }) {
  const classes =
    status === "executed"
      ? "bg-emerald-900/50 text-emerald-400"
      : status === "failed"
      ? "bg-red-900/50 text-red-400"
      : "bg-yellow-900/50 text-yellow-400";
  return (
    <span
      className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-mono font-semibold capitalize ${classes}`}
    >
      {status}
    </span>
  );
}

function ProviderBadge({ provider }: { provider: Signal["provider"] }) {
  const label = provider === "gp" ? "GP" : provider === "lumibot" ? "Lumibot" : "Manual";
  return (
    <span className="inline-flex items-center px-2 py-0.5 rounded text-xs font-mono bg-slate-800 text-slate-300 border border-slate-700">
      {label}
    </span>
  );
}

function TxLink({ hash }: { hash: string }) {
  return (
    <a
      href={`${EXPLORER_BASE}/${hash}`}
      target="_blank"
      rel="noopener noreferrer"
      className="text-blue-400 hover:text-blue-300 underline font-mono text-xs"
    >
      {hash.slice(0, 10)}…{hash.slice(-6)}
    </a>
  );
}

interface SignalTableProps {
  signals: Signal[];
}

export default function SignalTable({ signals }: SignalTableProps) {
  if (signals.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center py-24 text-slate-500">
        <svg
          className="mb-4 h-12 w-12 opacity-30"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth={1.5}
            d="M9 17v-2m3 2v-4m3 4v-6m2 10H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
          />
        </svg>
        <p className="text-sm font-medium">No signals yet</p>
        <p className="mt-1 text-xs">Submit a trade via the form below to get started.</p>
      </div>
    );
  }

  return (
    <div className="overflow-x-auto rounded-xl border border-slate-800">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b border-slate-800 bg-slate-900/80 text-left text-xs font-semibold uppercase tracking-wider text-slate-500">
            <th className="px-4 py-3">Timestamp</th>
            <th className="px-4 py-3">Provider</th>
            <th className="px-4 py-3">Asset</th>
            <th className="px-4 py-3">Direction</th>
            <th className="px-4 py-3 text-right">Size</th>
            <th className="px-4 py-3 text-right">Price</th>
            <th className="px-4 py-3">Status</th>
            <th className="px-4 py-3">TX Hash</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-slate-800 bg-slate-950/40">
          {signals.map((sig) => (
            <tr
              key={sig.id}
              className="hover:bg-slate-900/60 transition-colors"
            >
              <td className="whitespace-nowrap px-4 py-3 font-mono text-xs text-slate-400">
                {formatTimestamp(sig.timestamp)}
              </td>
              <td className="px-4 py-3">
                <ProviderBadge provider={sig.provider} />
              </td>
              <td className="whitespace-nowrap px-4 py-3 font-mono text-xs font-semibold text-slate-200">
                {sig.asset}
              </td>
              <td className="px-4 py-3">
                <DirectionBadge direction={sig.direction} />
              </td>
              <td className="whitespace-nowrap px-4 py-3 text-right font-mono text-xs text-slate-300">
                {sig.size.toLocaleString(undefined, { maximumFractionDigits: 4 })}
              </td>
              <td className="whitespace-nowrap px-4 py-3 text-right font-mono text-xs text-slate-300">
                ${sig.price.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
              </td>
              <td className="px-4 py-3">
                <StatusBadge status={sig.status} />
              </td>
              <td className="px-4 py-3">
                {sig.txHash ? <TxLink hash={sig.txHash} /> : <span className="text-slate-600 text-xs">—</span>}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
