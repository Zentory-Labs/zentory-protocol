"use client";

import { useState, useEffect, useRef } from "react";
import { useAccount, useDisconnect, useConnect } from "wagmi";

function shorten(addr: string): string {
  return `${addr.slice(0, 6)}...${addr.slice(-4)}`;
}

const WALLET_ICONS: Record<string, string> = {
  "MetaMask": "🦊",
  "Rabby": "🐰",
  "Coinbase": "💙",
  "WalletConnect": "🔗",
};

function getWalletIcon(name: string): string {
  const n = name.toLowerCase();
  if (n.includes("metamask")) return WALLET_ICONS["MetaMask"];
  if (n.includes("rabby")) return WALLET_ICONS["Rabby"];
  if (n.includes("coinbase")) return WALLET_ICONS["Coinbase"];
  if (n.includes("walletconnect")) return WALLET_ICONS["WalletConnect"];
  return "🌐";
}

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
        <div
          className="h-8 w-8 rounded-lg flex items-center justify-center border"
          style={{ background: "rgba(139, 30, 45, 0.2)", borderColor: "rgba(139, 30, 45, 0.4)" }}
        >
          <div className="h-2 w-2 rounded-full" style={{ background: "#b08d57" }} />
        </div>
        <span className="hidden sm:block font-mono text-xs" style={{ color: "#bfc3c7" }}>{shorten(address)}</span>
        <button
          onClick={() => disconnect()}
          className="rounded-lg border px-3 py-1.5 text-xs transition-all duration-300"
          style={{
            background: "transparent",
            borderColor: "#2a2f3a",
            color: "#6a6f75",
            fontFamily: "'Montserrat', sans-serif",
          }}
          onMouseEnter={(e) => {
            (e.currentTarget as HTMLButtonElement).style.borderColor = "#8b1e2d";
            (e.currentTarget as HTMLButtonElement).style.color = "#c2353f";
          }}
          onMouseLeave={(e) => {
            (e.currentTarget as HTMLButtonElement).style.borderColor = "#2a2f3a";
            (e.currentTarget as HTMLButtonElement).style.color = "#6a6f75";
          }}
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
          background: "rgba(139, 30, 45, 0.2)",
          borderColor: "rgba(139, 30, 45, 0.45)",
          color: "#c2353f",
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
            background: "rgba(20, 20, 23, 0.97)",
            backdropFilter: "blur(20px)",
            border: "1px solid #2a2f3a",
            boxShadow: "0 20px 60px rgba(0, 0, 0, 0.7), 0 0 30px rgba(139, 30, 45, 0.08)",
          }}
        >
          <div className="px-4 py-3" style={{ borderBottom: "1px solid #2a2f3a" }}>
            <p className="text-xs uppercase tracking-wider" style={{ color: "#6a6f75" }}>Select wallet</p>
          </div>
          <div className="py-2">
            {connectors.map((connector) => {
              const name = connector.name ?? "Unknown Wallet";
              return (
                <button
                  key={connector.uid}
                  onClick={() => {
                    connect({ connector });
                    setOpen(false);
                  }}
                  className="w-full flex items-center gap-3 px-4 py-3 transition-colors"
                  style={{ color: "#bfc3c7" }}
                  onMouseEnter={(e) => {
                    (e.currentTarget as HTMLButtonElement).style.background = "rgba(139, 30, 45, 0.08)";
                    (e.currentTarget as HTMLButtonElement).style.color = "#eaeaea";
                  }}
                  onMouseLeave={(e) => {
                    (e.currentTarget as HTMLButtonElement).style.background = "transparent";
                    (e.currentTarget as HTMLButtonElement).style.color = "#bfc3c7";
                  }}
                >
                  <span className="text-xl">{getWalletIcon(name)}</span>
                  <span className="text-sm font-medium" style={{ fontFamily: "'Montserrat', sans-serif" }}>{name}</span>
                </button>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
}
