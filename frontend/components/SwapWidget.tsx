"use client";

import { useState } from "react";
import Image from "next/image";
import { useAccount } from "wagmi";

const TOKENS = [
  { symbol: "ETH", name: "Ethereum", logo: "/token-logos/eth.png", price: 3450 },
  { symbol: "BTC", name: "Bitcoin", logo: "/token-logos/btc.png", price: 97500 },
  { symbol: "USDT", name: "Tether", logo: "/token-logos/usdt.png", price: 1.0 },
  { symbol: "SOL", name: "Solana", logo: "/token-logos/sol.png", price: 185 },
];

const ZENT_PRICE = 0.08; // mock ZENT price in USD

export function SwapWidget() {
  const { address, isConnected } = useAccount();
  const [fromToken, setFromToken] = useState("ZENT");
  const [toToken, setToToken] = useState("ETH");
  const [fromAmount, setFromAmount] = useState("");
  const [slippage, setSlippage] = useState(0.5);

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
        <div className="flex items-center gap-3">
          <input
            type="number"
            step="any"
            placeholder="0.00"
            value={fromAmount}
            onChange={(e) => setFromAmount(e.target.value)}
            className="flex-1 bg-transparent text-white text-2xl font-mono outline-none placeholder-white/20"
            style={{ fontFamily: "'Montserrat', sans-serif" }}
          />
          <div className="flex items-center gap-2">
            <select
              value={fromToken}
              onChange={(e) => setFromToken(e.target.value)}
              className="rounded-xl border px-3 py-2 text-sm font-medium cursor-pointer outline-none appearance-none"
              style={{
                background: "rgba(42,47,58,0.8)",
                borderColor: "#2a2f3a",
                color: "#eaeaea",
                fontFamily: "'Montserrat', sans-serif",
              }}
            >
              <option value="ZENT">ZENT</option>
              {TOKENS.map((t) => (
                <option key={t.symbol} value={t.symbol}>{t.symbol}</option>
              ))}
            </select>
          </div>
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
        <div className="flex items-center gap-3">
          <span
            className="flex-1 text-2xl font-mono text-white"
            style={{ fontFamily: "'Montserrat', sans-serif" }}
          >
            {estimatedOutput}
          </span>
          <select
            value={toToken}
            onChange={(e) => setToToken(e.target.value)}
            className="rounded-xl border px-3 py-2 text-sm font-medium cursor-pointer outline-none appearance-none"
            style={{
              background: "rgba(42,47,58,0.8)",
              borderColor: "#2a2f3a",
              color: "#eaeaea",
              fontFamily: "'Montserrat', sans-serif",
            }}
          >
            <option value="ZENT">ZENT</option>
            {TOKENS.map((t) => (
              <option key={t.symbol} value={t.symbol}>{t.symbol}</option>
            ))}
          </select>
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
