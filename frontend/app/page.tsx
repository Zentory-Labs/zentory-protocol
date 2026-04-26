"use client";

import { useAccount, useReadContract } from "wagmi";
import { VideoHero } from "@/components/VideoHero";
import { addresses, ZENT_ABI, VAULT_ABI, STAKING_ABI, vaultMeta } from "@/lib/contracts";

const VAULTS = [addresses.zETH, addresses.zBTC, addresses.zXRP, addresses.zSOL] as const;

// ─── Helpers ───────────────────────────────────────────────────────────────────

function fmt(value: bigint, decimals = 18, digits = 2): string {
  if (value === 0n) return "0";
  const div = 10n ** BigInt(decimals);
  return (Number(value / div)).toLocaleString(undefined, {
    minimumFractionDigits: 0,
    maximumFractionDigits: digits,
  });
}

function fmtUsd(value: bigint, decimals = 18, digits = 0): string {
  if (value === 0n) return "$0";
  const div = 10n ** BigInt(decimals);
  return `$${Number(value / div).toLocaleString(undefined, {
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
  })}`;
}

// ─── Token Logo ─────────────────────────────────────────────────────────────

function TokenLogo({ symbol }: { symbol: string }) {
  const logos: Record<string, { bg: string; fg: string; label: string }> = {
    ETH: { bg: "linear-gradient(135deg, #627eea 0%, #8b5cf6 100%)", fg: "#fff", label: "ETH" },
    BTC: { bg: "linear-gradient(135deg, #f7931a 0%, #c2353f 100%)", fg: "#fff", label: "₿" },
    XRP: { bg: "#23292f", fg: "#eaeaea", label: "XRP" },
    SOL: { bg: "linear-gradient(135deg, #9945ff 0%, #14f195 100%)", fg: "#fff", label: "SOL" },
  };
  const { bg, fg, label } = logos[symbol] ?? { bg: "#2a2f3a", fg: "#eaeaea", label: symbol };

  return (
    <div
      className="w-10 h-10 rounded-xl flex items-center justify-center text-xs font-bold flex-shrink-0"
      style={{ background: bg, color: fg, fontFamily: "'Montserrat', sans-serif" }}
    >
      {label}
    </div>
  );
}

// ─── Vault Card ───────────────────────────────────────────────────────────────

function VaultCard({ vault }: { vault: (typeof VAULTS)[number] }) {
  const meta = vaultMeta[vault];
  const totalAssets = useReadContract({ address: vault, abi: VAULT_ABI, functionName: "totalAssets" } as any);
  const navPerShare = useReadContract({ address: vault, abi: VAULT_ABI, functionName: "getNavPerShare" } as any);
  const tvl = (totalAssets.data as bigint) ?? 0n;

  return (
    <div
      className="p-5 rounded-2xl transition-all duration-300 group cursor-pointer"
      style={{
        background: "#1c1c21",
        border: "1px solid #2a2f3a",
      }}
      onMouseEnter={(e) => {
        (e.currentTarget as HTMLDivElement).style.borderColor = "#8b1e2d";
        (e.currentTarget as HTMLDivElement).style.boxShadow = "0 0 40px rgba(139, 30, 45, 0.15), 0 20px 40px rgba(0,0,0,0.4)";
        (e.currentTarget as HTMLDivElement).style.transform = "translateY(-2px)";
      }}
      onMouseLeave={(e) => {
        (e.currentTarget as HTMLDivElement).style.borderColor = "#2a2f3a";
        (e.currentTarget as HTMLDivElement).style.boxShadow = "none";
        (e.currentTarget as HTMLDivElement).style.transform = "translateY(0)";
      }}
    >
      <div className="flex items-center gap-3 mb-4">
        <TokenLogo symbol={meta.asset} />
        <div>
          <div className="font-semibold text-white text-sm" style={{ fontFamily: "'Montserrat', sans-serif" }}>
            {meta.name}
          </div>
          <div className="text-xs" style={{ color: "#bfc3c7" }}>{meta.symbol}</div>
        </div>
      </div>
      <div className="space-y-2">
        {[
          { label: "TVL", value: totalAssets.isLoading ? "—" : fmtUsd(tvl) },
          { label: "NAV / Share", value: navPerShare.isLoading ? "—" : fmt((navPerShare.data as bigint) ?? 0n) },
        ].map(({ label, value }) => (
          <div key={label} className="flex justify-between items-center">
            <span className="text-xs" style={{ color: "#6a6f75" }}>{label}</span>
            <span className="text-sm font-mono font-medium text-white">{value}</span>
          </div>
        ))}
      </div>
      <div
        className="mt-4 pt-3 flex items-center justify-between"
        style={{ borderTop: "1px solid #2a2f3a" }}
      >
        <span
          className="px-2.5 py-1 rounded-full text-xs font-semibold border"
          style={{
            background: "rgba(139, 30, 45, 0.15)",
            color: "#c2353f",
            borderColor: "rgba(139, 30, 45, 0.3)",
            fontFamily: "'Montserrat', sans-serif",
          }}
        >
          Live
        </span>
        <a
          href={`https://hypurrscan.io/address/${vault}`}
          target="_blank"
          rel="noopener noreferrer"
          className="inline-flex items-center gap-1 text-xs transition-colors"
          style={{ color: "#6a6f75" }}
          onMouseEnter={(e) => (e.currentTarget.style.color = "#b08d57")}
          onMouseLeave={(e) => (e.currentTarget.style.color = "#6a6f75")}
        >
          View
          <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
          </svg>
        </a>
      </div>
    </div>
  );
}

// ─── Chain Data ───────────────────────────────────────────────────────────────

function ChainStats() {
  const { address, isConnected } = useAccount();

  const zenTotalSupply = useReadContract({ address: addresses.ZENT, abi: ZENT_ABI, functionName: "totalSupply" } as any);
  const zenBalance = useReadContract({
    address: addresses.ZENT, abi: ZENT_ABI, functionName: "balanceOf",
    args: address ? [address] : undefined, query: { enabled: !!isConnected },
  } as any);
  const totalStaked = useReadContract({ address: addresses.ZENTStaking, abi: STAKING_ABI, functionName: "totalStaked" } as any);

  const zenFormatted = Number(((zenTotalSupply.data as bigint) ?? 0n) / 10n ** 27n).toLocaleString(undefined, { maximumFractionDigits: 0 });
  const stakedFormatted = fmt((totalStaked.data as bigint) ?? 0n);

  const statItems = [
    { label: "ZENT Supply", value: zenTotalSupply.isLoading ? "—" : `${zenFormatted}B`, accent: "#eaeaea" },
    { label: "ZENT Staked", value: totalStaked.isLoading ? "—" : stakedFormatted, accent: "#eaeaea" },
    { label: "Layer-1 Vaults", value: "4", accent: "#b08d57" },
    ...(isConnected && zenBalance.data !== undefined
      ? [{ label: "Your ZENT", value: Number(((zenBalance.data as bigint) ?? 0n) / 10n ** 18n).toLocaleString(), accent: "#b08d57" }]
      : []),
  ];

  return (
    <div className="flex flex-wrap justify-center lg:justify-start gap-6 md:gap-10">
      {statItems.map(({ label, value, accent }) => (
        <div key={label} className="text-center">
          <div
            className="text-2xl md:text-3xl font-bold"
            style={{ color: accent, fontFamily: "'Montserrat', sans-serif" }}
          >
            {value}
          </div>
          <div
            className="text-xs md:text-sm uppercase tracking-wider mt-1"
            style={{ color: "#6a6f75", fontFamily: "'Montserrat', sans-serif" }}
          >
            {label}
          </div>
        </div>
      ))}
    </div>
  );
}

// ─── Main Page ───────────────────────────────────────────────────────────────

export default function Home() {
  return (
    <div className="w-full overflow-x-hidden">

      {/* ── Video Hero ── */}
      <VideoHero>

        <div
          className="flex flex-col items-center text-center max-w-5xl mx-auto"
          style={{ paddingTop: "80px" }}
        >

          {/* Badge */}
          <div
            className="inline-flex items-center gap-2 px-4 py-2 rounded-full text-sm font-semibold mb-8 border"
            style={{
              background: "rgba(139, 30, 45, 0.15)",
              borderColor: "rgba(139, 30, 45, 0.4)",
              color: "#c2353f",
              fontFamily: "'Montserrat', sans-serif",
              letterSpacing: "0.05em",
            }}
          >
            <span
              className="w-2 h-2 rounded-full"
              style={{ background: "#c2353f", boxShadow: "0 0 8px #c2353f" }}
            />
            HyperEVM · Chain 998 · ERC-4626
          </div>

          {/* Main headline */}
          <h1
            className="text-6xl sm:text-7xl md:text-8xl lg:text-7xl xl:text-9xl font-bold mb-6 tracking-tight leading-none"
            style={{ fontFamily: "'Montserrat', sans-serif" }}
          >
            <span className="gradient-text-gold">Zentory</span>
            <br />
            <span style={{ color: "#eaeaea" }}>Protocol</span>
          </h1>

          {/* Subtitle */}
          <p
            className="text-lg md:text-xl lg:text-xl xl:text-2xl mb-6 max-w-2xl font-light leading-relaxed"
            style={{ color: "rgba(234, 234, 234, 0.75)" }}
          >
            AI-powered algorithmic trading vaults.
            <br />
            Alpha generation through systematic strategies.
          </p>

          <p
            className="text-sm md:text-base mb-12 max-w-xl"
            style={{ color: "#6a6f75" }}
          >
            Stake ZENT · Earn yield · Govern the protocol
          </p>

          {/* CTA buttons */}
          <div className="flex flex-col sm:flex-row gap-4 justify-center items-center mb-16">
            {/* Stake ZENT — primary red */}
            <a
              href="/stake"
              className="px-10 py-4 rounded-xl font-semibold text-sm transition-all duration-300 hover:scale-[1.03]"
              style={{
                background: "#8b1e2d",
                color: "#eaeaea",
                fontFamily: "'Montserrat', sans-serif",
                boxShadow: "0 0 40px rgba(139, 30, 45, 0.35)",
              }}
              onMouseEnter={(e) => {
                (e.currentTarget as HTMLAnchorElement).style.background = "#c2353f";
                (e.currentTarget as HTMLAnchorElement).style.boxShadow = "0 0 60px rgba(194, 53, 63, 0.5)";
              }}
              onMouseLeave={(e) => {
                (e.currentTarget as HTMLAnchorElement).style.background = "#8b1e2d";
                (e.currentTarget as HTMLAnchorElement).style.boxShadow = "0 0 40px rgba(139, 30, 45, 0.35)";
              }}
            >
              Stake ZENT
            </a>

            {/* Governance — gold */}
            <a
              href="/govern"
              className="px-10 py-4 rounded-xl font-semibold text-sm transition-all duration-300 hover:scale-[1.03] border"
              style={{
                background: "transparent",
                color: "#b08d57",
                borderColor: "rgba(176, 141, 87, 0.4)",
                fontFamily: "'Montserrat', sans-serif",
              }}
              onMouseEnter={(e) => {
                (e.currentTarget as HTMLAnchorElement).style.background = "rgba(176, 141, 87, 0.08)";
                (e.currentTarget as HTMLAnchorElement).style.borderColor = "rgba(176, 141, 87, 0.7)";
              }}
              onMouseLeave={(e) => {
                (e.currentTarget as HTMLAnchorElement).style.background = "transparent";
                (e.currentTarget as HTMLAnchorElement).style.borderColor = "rgba(176, 141, 87, 0.4)";
              }}
            >
              Governance
            </a>

            {/* Signal Dashboard — cool blue */}
            <a
              href="/signals"
              className="px-10 py-4 rounded-xl font-semibold text-sm transition-all duration-300 hover:scale-[1.03]"
              style={{
                background: "rgba(58, 123, 213, 0.12)",
                color: "#3a7bd5",
                border: "1px solid rgba(58, 123, 213, 0.3)",
                fontFamily: "'Montserrat', sans-serif",
              }}
              onMouseEnter={(e) => {
                (e.currentTarget as HTMLAnchorElement).style.background = "rgba(58, 123, 213, 0.2)";
                (e.currentTarget as HTMLAnchorElement).style.borderColor = "rgba(58, 123, 213, 0.55)";
              }}
              onMouseLeave={(e) => {
                (e.currentTarget as HTMLAnchorElement).style.background = "rgba(58, 123, 213, 0.12)";
                (e.currentTarget as HTMLAnchorElement).style.borderColor = "rgba(58, 123, 213, 0.3)";
              }}
            >
              Signal Dashboard
            </a>
          </div>

          {/* Live stats */}
          <ChainStats />
        </div>

        {/* Scroll indicator */}
        <div
          className="absolute bottom-10 left-1/2 -translate-x-1/2 flex flex-col items-center"
          style={{
            color: "#6a6f75",
            animation: "bounce 2s ease-in-out infinite",
          }}
        >
          <span
            className="text-xs uppercase tracking-widest mb-1"
            style={{ fontFamily: "'Montserrat', sans-serif", color: "#6a6f75" }}
          >
            Scroll
          </span>
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" style={{ color: "#8b1e2d" }}>
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 14l-7 7m0 0l-7-7m7 7V3" />
          </svg>
        </div>

      </VideoHero>

      {/* ── Vaults ── */}
      <section
        className="max-w-7xl mx-auto px-6 py-20 space-y-8"
        style={{ background: "#0b0b0d" }}
      >
        <div className="flex items-center gap-3 mb-2">
          <div className="h-px flex-1" style={{ background: "linear-gradient(to right, transparent, #2a2f3a, transparent)" }} />
          <div
            className="flex items-center gap-2 text-sm font-semibold"
            style={{ color: "#b08d57", fontFamily: "'Montserrat', sans-serif" }}
          >
            <span>⬡</span> Layer-1 Vaults
          </div>
          <div className="h-px flex-1" style={{ background: "linear-gradient(to right, transparent, #2a2f3a, transparent)" }} />
        </div>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          {VAULTS.map((v) => <VaultCard key={v} vault={v} />)}
        </div>
      </section>

    </div>
  );
}
