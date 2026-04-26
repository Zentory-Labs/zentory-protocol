"use client";

import { useState, useEffect, useRef } from "react";
import { useAccount, useDisconnect, useConnect } from "wagmi";

function shorten(addr: string): string {
  return `${addr.slice(0, 6)}...${addr.slice(-4)}`;
}

const WALLET_ICONS: Record<string, string> = {
  "MetaMask": "🦊",
  "Coinbase Wallet": "💙",
  "injected": "🌐",
};

export function WalletButton() {
  const { address, isConnected } = useAccount();
  const { disconnect } = useDisconnect();
  const { connect, connectors } = useConnect();
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  // Close on outside click
  useEffect(() => {
    if (!open) return;
    const handler = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, [open]);

  // Listen for open-wallet-modal event from Nav
  useEffect(() => {
    const handler = () => { if (!isConnected) setOpen(true); };
    window.addEventListener("open-wallet-modal", handler);
    return () => window.removeEventListener("open-wallet-modal", handler);
  }, [isConnected]);

  if (isConnected && address) {
    return (
      <div className="flex items-center gap-3">
        <div className="h-8 w-8 rounded-lg bg-[#0d80fa]/20 border border-[#0d80fa]/40 flex items-center justify-center">
          <div className="h-2 w-2 rounded-full bg-emerald-400" />
        </div>
        <span className="hidden sm:block font-mono text-xs text-white/70">{shorten(address)}</span>
        <button
          onClick={() => disconnect()}
          className="rounded-lg border border-white/20 bg-white/5 px-3 py-1.5 text-xs text-white/70 hover:text-white hover:border-white/40 hover:bg-white/10 transition-all duration-300"
        >
          Disconnect
        </button>
      </div>
    );
  }

  return (
    <div className="relative" ref={ref}>
      <button
        onClick={() => setOpen((v) => !v)}
        className="rounded-xl border px-4 py-2 text-xs font-medium transition-all duration-300 flex items-center gap-2"
        style={{
          background: "rgba(0, 229, 255, 0.08)",
          borderColor: "rgba(0, 229, 255, 0.25)",
          color: "#00e5ff",
          fontFamily: "'Montserrat', sans-serif",
        }}
      >
        <svg className="w-4 h-4" viewBox="0 0 24 24" fill="none">
          <rect x="2" y="6" width="20" height="14" rx="2" stroke="currentColor" strokeWidth="1.5"/>
          <path d="M16 12h.01M8 12h.01" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/>
          <path d="M6 10V8a2 2 0 012-2h8a2 2 0 012 2v8a2 2 0 01-2 2H8a2 2 0 01-2-2v-2" stroke="currentColor" strokeWidth="1.5"/>
        </svg>
        Connect Wallet
        <svg className={`w-3 h-3 transition-transform ${open ? "rotate-180" : ""}`} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
          <path d="M6 9l6 6 6-6"/>
        </svg>
      </button>

      {open && (
        <div
        className="absolute right-0 top-full mt-2 w-64 rounded-2xl overflow-hidden z-[100]"
        style={{
          background: "rgba(10, 13, 24, 0.95)",
          backdropFilter: "blur(20px)",
          border: "1px solid rgba(0, 229, 255, 0.15)",
          boxShadow: "0 20px 60px rgba(0, 0, 0, 0.6), 0 0 40px rgba(0, 229, 255, 0.05)",
        }}
      >
          <div className="px-4 py-3 border-b border-white/[0.06]">
            <p className="text-xs text-white/40 uppercase tracking-wider">Select wallet</p>
          </div>
          <div className="py-2">
            {connectors.map((connector) => {
              const name = connector.name ?? "Unknown Wallet";
              const icon = WALLET_ICONS[name] ?? WALLET_ICONS["injected"];
              return (
                <button
                  key={connector.uid}
                  onClick={() => {
                    connect({ connector });
                    setOpen(false);
                  }}
                  className="w-full flex items-center gap-3 px-4 py-3 hover:bg-white/5 transition-colors"
                >
                  <span className="text-xl">{icon}</span>
                  <span className="text-sm text-white/90 font-medium">{name}</span>
                </button>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
}
