"use client";

import { useState, useTransition } from "react";
import type { Asset, Direction } from "@/lib/signals";
import { logSignal, executeSignal } from "@/lib/signals";

const ASSETS: Asset[] = ["BTC", "ETH", "XRP", "SOL"];
const DIRECTIONS: Direction[] = ["LONG", "SHORT", "CLOSE"];

type Toast = { kind: "success" | "error"; message: string } | null;

export default function TradeLoggerForm() {
  const [asset, setAsset] = useState<Asset>("BTC");
  const [direction, setDirection] = useState<Direction>("LONG");
  const [size, setSize] = useState<string>("");
  const [price, setPrice] = useState<string>("");
  const [toast, setToast] = useState<Toast>(null);
  const [isPending, startTransition] = useTransition();

  function showToast(kind: "success" | "error", message: string) {
    setToast({ kind, message });
    setTimeout(() => setToast(null), 4000);
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    const sizeNum = parseFloat(size);
    const priceNum = parseFloat(price);
    if (isNaN(sizeNum) || isNaN(priceNum) || sizeNum <= 0 || priceNum <= 0) {
      showToast("error", "Please enter valid size and price values.");
      return;
    }
    startTransition(async () => {
      try {
        const signal = await logSignal({ asset, direction, size: sizeNum, price: priceNum });
        showToast("success", `Signal logged (${signal.id}). Ready to execute.`);
        setSize("");
        setPrice("");
      } catch {
        showToast("error", "Failed to log signal. Please try again.");
      }
    });
  }

  async function handleExecute() {
    const sizeNum = parseFloat(size);
    const priceNum = parseFloat(price);
    if (isNaN(sizeNum) || isNaN(priceNum)) {
      showToast("error", "Enter size and price before executing.");
      return;
    }
    startTransition(async () => {
      try {
        const signal = await logSignal({ asset, direction, size: sizeNum, price: priceNum });
        const result = await executeSignal(signal);
        showToast("success", `Trade executed. TX: ${result.txHash.slice(0, 12)}…`);
        setSize("");
        setPrice("");
      } catch {
        showToast("error", "Execution failed. Check keeper key and RPC URL.");
      }
    });
  }

  return (
    <div className="rounded-xl border border-slate-800 bg-slate-950/60 p-6">
      <h2 className="mb-5 text-lg font-semibold text-slate-100">Log Trade Signal</h2>

      {toast && (
        <div
          className={`mb-4 flex items-center gap-3 rounded-lg px-4 py-3 text-sm font-medium border ${
            toast.kind === "success"
              ? "bg-emerald-950/60 text-emerald-400 border-emerald-800"
              : "bg-red-950/60 text-red-400 border-red-800"
          }`}
        >
          {toast.kind === "success" ? (
            <svg className="h-4 w-4 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
            </svg>
          ) : (
            <svg className="h-4 w-4 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          )}
          {toast.message}
        </div>
      )}

      <form onSubmit={handleSubmit} className="space-y-5">
        <div className="grid grid-cols-1 gap-5 sm:grid-cols-2">
          <div>
            <label className="mb-1.5 block text-xs font-medium text-slate-500 uppercase tracking-wider">
              Asset
            </label>
            <select
              value={asset}
              onChange={(e) => setAsset(e.target.value as Asset)}
              className="w-full cursor-pointer rounded-lg border border-slate-700 bg-slate-900 px-3 py-2.5 text-sm font-mono text-slate-200 outline-none focus:border-blue-600 focus:ring-1 focus:ring-blue-600 transition-colors"
            >
              {ASSETS.map((a) => (
                <option key={a} value={a}>
                  {a}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label className="mb-1.5 block text-xs font-medium text-slate-500 uppercase tracking-wider">
              Size
            </label>
            <div className="flex gap-2">
              <input
                type="number"
                step="any"
                min="0"
                placeholder="0.00"
                value={size}
                onChange={(e) => setSize(e.target.value)}
                className="flex-1 cursor-pointer rounded-lg border border-slate-700 bg-slate-900 px-3 py-2.5 text-sm font-mono text-slate-200 outline-none focus:border-blue-600 focus:ring-1 focus:ring-blue-600 transition-colors"
              />
              <button
                type="button"
                onClick={() => setSize("1")}
                className="shrink-0 rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-xs font-mono text-slate-400 hover:bg-slate-700 hover:text-slate-200 transition-colors"
              >
                MAX
              </button>
            </div>
          </div>
        </div>

        <div>
          <label className="mb-1.5 block text-xs font-medium text-slate-500 uppercase tracking-wider">
            Direction
          </label>
          <div className="flex gap-3">
            {DIRECTIONS.map((d) => {
              const isSelected = direction === d;
              const activeClass =
                d === "LONG"
                  ? isSelected
                    ? "bg-emerald-900/70 text-emerald-300 border-emerald-600"
                    : "hover:bg-emerald-950/50 text-emerald-500 border-slate-700"
                  : d === "SHORT"
                  ? isSelected
                    ? "bg-red-900/70 text-red-300 border-red-600"
                    : "hover:bg-red-950/50 text-red-500 border-slate-700"
                  : isSelected
                  ? "bg-slate-700 text-slate-200 border-slate-500"
                  : "hover:bg-slate-800 text-slate-400 border-slate-700";
              return (
                <button
                  key={d}
                  type="button"
                  onClick={() => setDirection(d)}
                  className={`flex-1 rounded-lg border py-2.5 text-sm font-semibold font-mono uppercase tracking-wider transition-all ${activeClass}`}
                >
                  {d}
                </button>
              );
            })}
          </div>
        </div>

        <div>
          <label className="mb-1.5 block text-xs font-medium text-slate-500 uppercase tracking-wider">
            Price (USD)
          </label>
          <input
            type="number"
            step="any"
            min="0"
            placeholder="0.00"
            value={price}
            onChange={(e) => setPrice(e.target.value)}
            className="w-full cursor-pointer rounded-lg border border-slate-700 bg-slate-900 px-3 py-2.5 text-sm font-mono text-slate-200 outline-none focus:border-blue-600 focus:ring-1 focus:ring-blue-600 transition-colors"
          />
        </div>

        <div className="flex gap-3 pt-2">
          <button
            type="submit"
            disabled={isPending}
            className="flex-1 rounded-lg border border-slate-700 bg-slate-800 py-2.5 text-sm font-semibold text-slate-200 hover:bg-slate-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
          >
            {isPending ? "Logging…" : "Log Signal"}
          </button>
          <button
            type="button"
            disabled={isPending}
            onClick={handleExecute}
            className="flex-1 rounded-lg bg-blue-700 py-2.5 text-sm font-semibold text-white hover:bg-blue-600 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
          >
            {isPending ? "Executing…" : "Execute Trade"}
          </button>
        </div>
      </form>
    </div>
  );
}
