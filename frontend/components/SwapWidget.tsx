"use client";

import { useState, useRef } from "react";
import { useAccount } from "wagmi";
import { TokenSelect } from "./TokenSelect";

const TOKENS = [
  { symbol: "ETH" as const, name: "Ethereum", price: 3450 },
  { symbol: "BTC" as const, name: "Bitcoin", price: 97500 },
  { symbol: "USDT" as const, name: "Tether", price: 1.0 },
  { symbol: "SOL" as const, name: "Solana", price: 185 },
];

const ZENT_PRICE = 0.08; // mock ZENT price in USD

const PRESET_AMOUNTS = [100, 1000, 10000];

function PlusIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.5} strokeLinecap="round">
      <path d="M12 5v14M5 12h14" />
    </svg>
  );
}

function MinusIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.5} strokeLinecap="round">
      <path d="M5 12h14" />
    </svg>
  );
}

export function SwapWidget() {
  const { address, isConnected } = useAccount();
  const [fromToken, setFromToken] = useState<"ZENT" | "ETH" | "BTC" | "USDT" | "SOL">("ZENT");
  const [toToken, setToToken] = useState<"ZENT" | "ETH" | "BTC" | "USDT" | "SOL">("ETH");
  const [fromAmount, setFromAmount] = useState("");
  const [slippage, setSlippage] = useState(0.5);
  const inputRef = useRef<HTMLInputElement>(null);

  const toTokenData = TOKENS.find((t) => t.symbol === toToken)!;
  const fromPrice = fromToken === "ZENT" ? ZENT_PRICE : TOKENS.find((t) => t.symbol === fromToken)?.price ?? 1;
  const toPrice = toToken === "ZENT" ? ZENT_PRICE : toTokenData.price;
  const estimatedOutput =
    fromAmount && !isNaN(parseFloat(fromAmount))
      ? (parseFloat(fromAmount) * fromPrice / toPrice).toFixed(6)
      : "0.000000";

  const handleSwap = () => {
    if (!isConnected) return;
    // Mock swap — would connect to DEX contract in production
    alert(`Swap ${fromAmount} ${fromToken} → ${estimatedOutput} ${toToken}\n(Swap contract integration coming soon)`);
  };

  const handleBlur = () => {
    window.scrollTo({ top: 0, behavior: "smooth" });
  };

  const adjustAmount = (delta: number) => {
    const current = parseFloat(fromAmount) || 0;
    const next = Math.max(0, current + delta);
    setFromAmount(next === 0 ? "" : String(next));
  };

  return (
    <div
      className="rounded-2xl p-5 w-full max-w-sm"
      style={{
        background: "rgba(28, 28, 33, 0.9)",
        backdropFilter: "blur(20px)",
        border: "1px solid #2a2f3a",
      }}
    >
      {/* Header */}
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-2">
          <div
            className="w-8 h-8 rounded-xl flex items-center justify-center text-xs font-bold border"
            style={{ background: "rgba(176,141,87,0.15)", borderColor: "rgba(176,141,87,0.3)", color: "#b08d57", fontFamily: "'Montserrat', sans-serif" }}
          >
            Z
          </div>
          <span className="font-semibold text-white text-sm" style={{ fontFamily: "'Montserrat', sans-serif" }}>
            ZENT Swap
          </span>
        </div>
        <div className="flex items-center gap-1">
          {[0.5, 1.0, 3.0].map((s) => (
            <button
              key={s}
              onClick={() => setSlippage(s)}
              className="px-2 py-0.5 rounded text-xs font-medium transition-all"
              style={{
                background: slippage === s ? "rgba(139,30,45,0.3)" : "transparent",
                color: slippage === s ? "#c2353f" : "#6a6f75",
                border: `1px solid ${slippage === s ? "rgba(139,30,45,0.5)" : "#2a2f3a"}`,
                fontFamily: "'Montserrat', sans-serif",
              }}
            >
              {s}%
            </button>
          ))}
        </div>
      </div>

      {/* From */}
      <div
        className="rounded-xl p-4 mb-2"
        style={{ background: "rgba(11,11,13,0.6)", border: "1px solid #2a2f3a" }}
      >
        <div className="flex items-center justify-between mb-2">
          <span className="text-xs" style={{ color: "#6a6f75" }}>From</span>
          <span className="text-xs" style={{ color: "#6a6f75" }}>
            Balance: 1,250.00
          </span>
        </div>

        {/* Preset amount quick-select */}
        <div className="flex gap-2 mb-3">
          {PRESET_AMOUNTS.map((amt) => (
            <button
              key={amt}
              onClick={() => setFromAmount(String(amt))}
              className="flex-1 text-xs py-1 rounded-lg border transition-all hover:border-white/40 active:scale-95"
              style={{
                borderColor: fromAmount === String(amt) ? "rgba(139,30,45,0.7)" : "rgba(42,47,58,0.8)",
                background: fromAmount === String(amt) ? "rgba(139,30,45,0.2)" : "transparent",
                color: fromAmount === String(amt) ? "#c2353f" : "rgba(106,111,117,0.9)",
                fontFamily: "'Montserrat', sans-serif",
              }}
            >
              {amt.toLocaleString()}
            </button>
          ))}
        </div>

        {/* Input row with +/- controls */}
        <div className="flex items-center gap-2 min-w-0">
          <button
            onClick={() => adjustAmount(-10)}
            className="w-8 h-8 rounded-lg border flex items-center justify-center flex-shrink-0 transition-all hover:border-white/40 active:scale-95"
            style={{ background: "rgba(42,47,58,0.5)", borderColor: "#2a2f3a", color: "#6a6f75" }}
            aria-label="Decrease amount"
          >
            <MinusIcon />
          </button>
          <input
            ref={inputRef}
            type="text"
            inputMode="decimal"
            step="any"
            placeholder="0.00"
            value={fromAmount}
            onChange={(e) => setFromAmount(e.target.value)}
            onBlur={handleBlur}
            className="flex-1 min-w-0 bg-transparent text-white text-2xl font-mono outline-none placeholder-white/20 text-right"
            style={{ fontFamily: "'Montserrat', sans-serif" }}
          />
          <button
            onClick={() => adjustAmount(10)}
            className="w-8 h-8 rounded-lg border flex items-center justify-center flex-shrink-0 transition-all hover:border-white/40 active:scale-95"
            style={{ background: "rgba(42,47,58,0.5)", borderColor: "#2a2f3a", color: "#6a6f75" }}
            aria-label="Increase amount"
          >
            <PlusIcon />
          </button>
          <TokenSelect
            value={fromToken}
            onChange={(v) => setFromToken(v as typeof fromToken)}
          />
        </div>
        <div className="mt-1 text-xs" style={{ color: "#6a6f75" }}>
          ≈ ${fromAmount && !isNaN(parseFloat(fromAmount)) ? (parseFloat(fromAmount) * fromPrice).toFixed(2) : "0.00"} USD
        </div>
      </div>

      {/* Swap direction indicator */}
      <div className="flex justify-center -my-1 relative z-10">
        <button
          onClick={() => {
            const tmp = fromToken;
            setFromToken(toToken);
            setToToken(tmp);
          }}
          className="w-8 h-8 rounded-xl border flex items-center justify-center transition-all hover:scale-110"
          style={{
            background: "#1c1c21",
            borderColor: "#8b1e2d",
          }}
          title="Swap direction"
        >
          <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="#c2353f" strokeWidth={2}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M7 16V4m0 0L3 8m4-4l4 4M17 8v12m0 0l4-4m-4 4l-4-4" />
          </svg>
        </button>
      </div>

      {/* To */}
      <div
        className="rounded-xl p-4 mb-4"
        style={{ background: "rgba(11,11,13,0.6)", border: "1px solid #2a2f3a" }}
      >
        <div className="flex items-center justify-between mb-2">
          <span className="text-xs" style={{ color: "#6a6f75" }}>To</span>
          <span className="text-xs" style={{ color: "#6a6f75" }}>Balance: —
          </span>
        </div>
        <div className="flex items-center gap-3 min-w-0">
          <span
            className="flex-1 min-w-0 text-2xl font-mono text-white"
            style={{ fontFamily: "'Montserrat', sans-serif" }}
          >
            {estimatedOutput}
          </span>
          <TokenSelect
            value={toToken}
            onChange={(v) => setToToken(v as typeof toToken)}
          />
        </div>
        <div className="mt-1 text-xs" style={{ color: "#6a6f75" }}>
          ≈ ${fromAmount && !isNaN(parseFloat(fromAmount)) ? (parseFloat(estimatedOutput) * toPrice).toFixed(2) : "0.00"} USD
        </div>
      </div>

      {/* Details row */}
      <div className="flex justify-between text-xs mb-4 px-1">
        <span style={{ color: "#6a6f75" }}>Rate</span>
        <span className="font-mono" style={{ color: "#bfc3c7" }}>
          1 {fromToken} = {(fromPrice / toPrice).toFixed(6)} {toToken}
        </span>
      </div>
      <div className="flex justify-between text-xs mb-4 px-1">
        <span style={{ color: "#6a6f75" }}>Slippage</span>
        <span className="font-mono" style={{ color: "#bfc3c7" }}>{slippage}%</span>
      </div>

      {/* CTA */}
      <button
        onClick={handleSwap}
        disabled={!isConnected || !fromAmount || parseFloat(fromAmount) <= 0}
        className="w-full rounded-xl font-semibold py-3.5 text-sm transition-all duration-300 disabled:opacity-40 disabled:cursor-not-allowed"
        style={{
          background: isConnected ? "#8b1e2d" : "#8b1e2d",
          color: "#eaeaea",
          fontFamily: "'Montserrat', sans-serif",
          boxShadow: "0 0 30px rgba(139,30,45,0.3)",
        }}
        onMouseEnter={(e) => { if (isConnected && fromAmount) (e.currentTarget as HTMLButtonElement).style.background = "#c2353f"; }}
        onMouseLeave={(e) => { (e.currentTarget as HTMLButtonElement).style.background = "#8b1e2d"; }}
      >
        {!isConnected
          ? "Connect Wallet"
          : !fromAmount || parseFloat(fromAmount) <= 0
          ? "Enter Amount"
          : `Swap ${fromToken} → ${toToken}`}
      </button>

      {/* Powered by line */}
      <p className="text-center text-xs mt-3" style={{ color: "#6a6f75" }}>
        Powered by Zentory Protocol · HyperEVM
      </p>
    </div>
  );
}
