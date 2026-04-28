"use client";

import { useState, useEffect, useRef } from "react";
import { useAccount, useDisconnect, useConnect, useChainId, useSwitchChain } from "wagmi";

const HYPER_EVM_CHAIN_ID = 998;

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
  const { address, isConnected, isConnecting } = useAccount();
  const { disconnect } = useDisconnect();
  const { connect, connectors } = useConnect();
  const chainId = useChainId();
  const { switchChain } = useSwitchChain();

  const [open, setOpen] = useState(false);
  const [connectionError, setConnectionError] = useState<string | null>(null);
  const [connectionTimeoutId, setConnectionTimeoutId] = useState<ReturnType<typeof setTimeout> | null>(null);
  const ref = useRef<HTMLDivElement>(null);

  const wrongNetwork = isConnected && chainId !== HYPER_EVM_CHAIN_ID;
  const noWallet = typeof window !== "undefined" && !(window as Window & { ethereum?: unknown }).ethereum;

  // Clear connection error when modal opens
  useEffect(() => {
    if (open) setConnectionError(null);
  }, [open]);

  // Set up connection timeout when connecting starts
  useEffect(() => {
    if (isConnecting) {
      const timer = setTimeout(() => {
        setConnectionError("Connection timed out. Try again or use a different wallet.");
      }, 15000);
      setConnectionTimeoutId(timer);
      return () => clearTimeout(timer);
    } else {
      if (connectionTimeoutId) {
        clearTimeout(connectionTimeoutId);
        setConnectionTimeoutId(null);
      }
    }
  }, [isConnecting]);

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

  // Auto-reconnect on mount using last connected connector
  useEffect(() => {
    if (isConnected || isConnecting) return;
    const lastConnectorUid = localStorage.getItem("lastConnector");
    if (!lastConnectorUid) return;
    const connector = connectors.find(c => c.uid === lastConnectorUid);
    if (!connector) return;
    setOpen(false);
    setConnectionError(null);
    connect({ connector });
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function handleConnect(connectorUid: string) {
    const connector = connectors.find(c => c.uid === connectorUid);
    if (!connector) return;
    setConnectionError(null);
    try {
      connect({ connector });
      localStorage.setItem("lastConnector", connectorUid);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      if (msg.includes("rejected") || msg.includes("denied") || msg.includes("cancelled") || msg.includes("rejected the request")) {
        setConnectionError("Connection rejected. Please approve the request in your wallet.");
      } else if (msg.includes("timeout")) {
        setConnectionError("Connection timed out. Try again or use a different wallet.");
      } else {
        setConnectionError(msg || "Failed to connect. Please try again.");
      }
    }
  }

  function handleSwitchNetwork() {
    switchChain({ chainId: HYPER_EVM_CHAIN_ID });
  }

  if (isConnected && address) {
    return (
      <div className="flex items-center gap-3">
        {/* Network indicator dot */}
        <div
          className="h-8 w-8 rounded-lg flex items-center justify-center border"
          style={{ background: wrongNetwork ? "rgba(239,68,68,0.15)" : "rgba(139,30,45,0.2)", borderColor: wrongNetwork ? "rgba(239,68,68,0.4)" : "rgba(139,30,45,0.4)" }}
          title={wrongNetwork ? "Wrong network — switch to HyperEVM Testnet" : "HyperEVM Testnet"}
        >
          <div className="h-2 w-2 rounded-full" style={{ background: wrongNetwork ? "#ef4444" : "#b08d57", boxShadow: wrongNetwork ? "0 0 8px #ef4444" : "0 0 8px #b08d57" }} />
        </div>

        <span className="hidden sm:block font-mono text-xs" style={{ color: "#bfc3c7" }}>{shorten(address)}</span>

        {wrongNetwork ? (
          <button
            onClick={handleSwitchNetwork}
            className="rounded-lg border px-3 py-1.5 text-xs transition-all duration-300"
            style={{
              background: "rgba(239,68,68,0.1)",
              borderColor: "rgba(239,68,68,0.4)",
              color: "#ef4444",
              fontFamily: "'Montserrat', sans-serif",
            }}
            onMouseEnter={(e) => {
              (e.currentTarget as HTMLButtonElement).style.borderColor = "#ef4444";
              (e.currentTarget as HTMLButtonElement).style.background = "rgba(239,68,68,0.2)";
            }}
            onMouseLeave={(e) => {
              (e.currentTarget as HTMLButtonElement).style.borderColor = "rgba(239,68,68,0.4)";
              (e.currentTarget as HTMLButtonElement).style.background = "rgba(239,68,68,0.1)";
            }}
          >
            Switch Network
          </button>
        ) : (
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
        )}
      </div>
    );
  }

  return (
    <div className="relative" ref={ref}>
      <button
        onClick={() => setOpen((v) => !v)}
        disabled={isConnecting}
        className="rounded-xl border px-4 py-2 text-xs font-medium transition-all duration-300 flex items-center gap-2"
        style={{
          background: isConnecting ? "rgba(139,30,45,0.1)" : "rgba(139,30,45,0.2)",
          borderColor: isConnecting ? "rgba(139,30,45,0.3)" : "rgba(139,30,45,0.45)",
          color: isConnecting ? "#b08d57" : "#c2353f",
          fontFamily: "'Montserrat', sans-serif",
        }}
      >
        {isConnecting ? (
          <>
            <svg className="w-4 h-4 animate-spin" viewBox="0 0 24 24" fill="none">
              <circle cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="2" strokeOpacity="0.3" />
              <path d="M12 2a10 10 0 0110 10" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
            </svg>
            Connecting…
          </>
        ) : (
          <>
            <svg className="w-4 h-4" viewBox="0 0 24 24" fill="none">
              <rect x="2" y="6" width="20" height="14" rx="2" stroke="currentColor" strokeWidth="1.5"/>
              <path d="M16 12h.01M8 12h.01" stroke="currentColor" strokeWidth="2" strokeLinecap="round"/>
              <path d="M6 10V8a2 2 0 012-2h8a2 2 0 012 2v8a2 2 0 01-2 2H8a2 2 0 01-2-2v-2" stroke="currentColor" strokeWidth="1.5"/>
            </svg>
            Connect Wallet
          </>
        )}
        {!isConnecting && (
          <svg className={`w-3 h-3 transition-transform ${open ? "rotate-180" : ""}`} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <path d="M6 9l6 6 6-6"/>
          </svg>
        )}
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

          {noWallet && (
            <div className="px-4 py-3" style={{ borderBottom: "1px solid #2a2f3a" }}>
              <p className="text-xs" style={{ color: "#ef4444", fontFamily: "'Montserrat', sans-serif" }}>
                No wallet detected. Install MetaMask or use WalletConnect.
              </p>
            </div>
          )}

          {connectionError && (
            <div className="px-4 py-2" style={{ borderBottom: "1px solid #2a2f3a" }}>
              <p className="text-xs" style={{ color: "#ef4444", fontFamily: "'Montserrat', sans-serif" }}>
                {connectionError}
              </p>
            </div>
          )}

          <div className="py-2">
            {connectors.map((connector) => {
              const name = connector.name ?? "Unknown Wallet";
              return (
                <button
                  key={connector.uid}
                  onClick={() => {
                    handleConnect(connector.uid);
                    if (!isConnecting) setOpen(false);
                  }}
                  disabled={isConnecting}
                  className="w-full flex items-center gap-3 px-4 py-3 transition-colors disabled:opacity-50"
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
