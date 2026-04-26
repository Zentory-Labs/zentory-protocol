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

// ─── Vault Card ───────────────────────────────────────────────────────────────

function VaultCard({ vault }: { vault: (typeof VAULTS)[number] }) {
  const meta = vaultMeta[vault];
  const totalAssets = useReadContract({ address: vault, abi: VAULT_ABI, functionName: "totalAssets" } as any);
  const navPerShare = useReadContract({ address: vault, abi: VAULT_ABI, functionName: "getNavPerShare" } as any);
  const tvl = (totalAssets.data as bigint) ?? 0n;

  return (
    <div
      className="p-5 border rounded-2xl transition-all duration-300 group cursor-pointer"
      style={{
        background: "rgba(10, 13, 24, 0.85)",
        borderColor: "rgba(0, 229, 255, 0.12)",
      }}
      onMouseEnter={(e) => {
        (e.currentTarget as HTMLDivElement).style.borderColor = "rgba(0, 229, 255, 0.4)";
        (e.currentTarget as HTMLDivElement).style.boxShadow = "0 0 40px rgba(0, 229, 255, 0.08)";
        (e.currentTarget as HTMLDivElement).style.transform = "translateY(-2px)";
      }}
      onMouseLeave={(e) => {
        (e.currentTarget as HTMLDivElement).style.borderColor = "rgba(0, 229, 255, 0.12)";
        (e.currentTarget as HTMLDivElement).style.boxShadow = "none";
        (e.currentTarget as HTMLDivElement).style.transform = "translateY(0)";
      }}
    >
      <div className="flex items-center gap-3 mb-4">
        <div
          className="w-10 h-10 rounded-xl flex items-center justify-center text-sm font-bold border"
          style={{
            background: "rgba(0, 229, 255, 0.1)",
            borderColor: "rgba(0, 229, 255, 0.2)",
            color: "#00e5ff",
          }}
        >
          {meta.asset}
        </div>
        <div>
          <div className="font-semibold text-white text-sm" style={{ fontFamily: "'Montserrat', sans-serif" }}>
            {meta.name}
          </div>
          <div className="text-xs" style={{ color: "rgba(232, 230, 240, 0.4)" }}>{meta.symbol}</div>
        </div>
      </div>
      <div className="space-y-2">
        {[
          { label: "TVL", value: totalAssets.isLoading ? "—" : fmtUsd(tvl) },
          { label: "NAV / Share", value: navPerShare.isLoading ? "—" : fmt((navPerShare.data as bigint) ?? 0n) },
        ].map(({ label, value }) => (
          <div key={label} className="flex justify-between items-center">
            <span className="text-xs" style={{ color: "rgba(232, 230, 240, 0.45)" }}>{label}</span>
            <span className="text-sm font-mono font-medium text-white">{value}</span>
          </div>
        ))}
      </div>
      <div
        className="mt-4 pt-3 flex items-center justify-between"
        style={{ borderTop: "1px solid rgba(0, 229, 255, 0.08)" }}
      >
        <span
          className="px-2.5 py-1 rounded-full text-xs font-semibold border"
          style={{
            background: "rgba(0, 229, 255, 0.12)",
            color: "#00e5ff",
            borderColor: "rgba(0, 229, 255, 0.25)",
          }}
        >
          Live
        </span>
        <a
          href={`https://hypurrscan.io/address/${vault}`}
          target="_blank"
          rel="noopener noreferrer"
          className="inline-flex items-center gap-1 text-xs transition-colors"
          style={{ color: "rgba(232, 230, 240, 0.4)" }}
          onMouseEnter={(e) => (e.currentTarget.style.color = "#00e5ff")}
          onMouseLeave={(e) => (e.currentTarget.style.color = "rgba(232, 230, 240, 0.4)")}
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
    { label: "ZENT Supply", value: zenTotalSupply.isLoading ? "—" : `${zenFormatted}B` },
    { label: "ZENT Staked", value: totalStaked.isLoading ? "—" : stakedFormatted },
    { label: "Alpha Vaults", value: "4", accent: "#00e5ff" },
    ...(isConnected && zenBalance.data !== undefined
      ? [{ label: "Your ZENT", value: Number(((zenBalance.data as bigint) ?? 0n) / 10n ** 18n).toLocaleString() }]
      : []),
  ];

  return (
    <div className="flex flex-wrap justify-center lg:justify-start gap-6 md:gap-10">
      {statItems.map(({ label, value, accent }) => (
        <div key={label} className="text-center">
          <div
            className="text-2xl md:text-3xl font-bold"
            style={{ color: accent ?? "white", fontFamily: "'Montserrat', sans-serif" }}
          >
            {value}
          </div>
          <div
            className="text-xs md:text-sm uppercase tracking-wider mt-1"
            style={{ color: "rgba(232, 230, 240, 0.55)", fontFamily: "'Montserrat', sans-serif" }}
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

        <div className="flex flex-col items-center text-center max-w-5xl mx-auto">

          {/* Badge */}
          <div
            className="inline-flex items-center gap-2 px-4 py-2 rounded-full text-sm font-semibold mb-8 border"
            style={{
              background: "rgba(0, 229, 255, 0.08)",
              borderColor: "rgba(0, 229, 255, 0.25)",
              color: "#00e5ff",
              fontFamily: "'Montserrat', sans-serif",
              letterSpacing: "0.05em",
            }}
          >
            <span
              className="w-2 h-2 rounded-full"
              style={{ background: "#00e5ff", boxShadow: "0 0 8px #00e5ff" }}
            />
            HyperEVM · Chain 998 · ERC-4626
          </div>

          {/* Main headline */}
          <h1
            className="text-6xl sm:text-7xl md:text-8xl lg:text-7xl xl:text-9xl font-bold text-white mb-6 tracking-tight leading-none"
            style={{ fontFamily: "'Montserrat', sans-serif" }}
          >
            <span className="gradient-text">Zentory</span>
            <br />
            <span className="text-white">Protocol</span>
          </h1>

          {/* Subtitle */}
          <p
            className="text-lg md:text-xl lg:text-xl xl:text-2xl mb-6 max-w-2xl font-light leading-relaxed"
            style={{ color: "rgba(232, 230, 240, 0.8)" }}
          >
            AI-powered algorithmic trading vaults.
            <br />
            Alpha generation through systematic strategies.
          </p>

          <p
            className="text-sm md:text-base mb-12 max-w-xl"
            style={{ color: "rgba(232, 230, 240, 0.45)" }}
          >
            Stake ZENT · Earn yield · Govern the protocol
          </p>

          {/* CTA buttons */}
          <div className="flex flex-col sm:flex-row gap-4 justify-center items-center mb-16">
            <a
              href="/stake"
              className="px-10 py-4 rounded-xl font-semibold text-sm transition-all duration-300 hover:scale-[1.03] hover:shadow-lg"
              style={{
                background: "#00e5ff",
                color: "#030508",
                fontFamily: "'Montserrat', sans-serif",
                boxShadow: "0 0 40px rgba(0, 229, 255, 0.3)",
              }}
              onMouseEnter={(e) => {
                (e.currentTarget as HTMLAnchorElement).style.background = "#00e5ff";
                (e.currentTarget as HTMLAnchorElement).style.boxShadow = "0 0 60px rgba(0, 229, 255, 0.45)";
              }}
              onMouseLeave={(e) => {
                (e.currentTarget as HTMLAnchorElement).style.background = "#00e5ff";
                (e.currentTarget as HTMLAnchorElement).style.boxShadow = "0 0 40px rgba(0, 229, 255, 0.3)";
              }}
            >
              Stake ZENT
            </a>
            <a
              href="/govern"
              className="px-10 py-4 rounded-xl font-semibold text-sm transition-all duration-300 hover:scale-[1.03] border"
              style={{
                background: "transparent",
                color: "#ff2d6a",
                borderColor: "rgba(255, 45, 106, 0.4)",
                fontFamily: "'Montserrat', sans-serif",
              }}
              onMouseEnter={(e) => {
                (e.currentTarget as HTMLAnchorElement).style.background = "rgba(255, 45, 106, 0.08)";
                (e.currentTarget as HTMLAnchorElement).style.borderColor = "rgba(255, 45, 106, 0.7)";
              }}
              onMouseLeave={(e) => {
                (e.currentTarget as HTMLAnchorElement).style.background = "transparent";
                (e.currentTarget as HTMLAnchorElement).style.borderColor = "rgba(255, 45, 106, 0.4)";
              }}
            >
              Governance
            </a>
            <a
              href="/signals"
              className="px-10 py-4 rounded-xl font-semibold text-sm transition-all duration-300 hover:scale-[1.03]"
              style={{
                background: "rgba(157, 0, 255, 0.15)",
                color: "#9d00ff",
                border: "1px solid rgba(157, 0, 255, 0.35)",
                fontFamily: "'Montserrat', sans-serif",
              }}
              onMouseEnter={(e) => {
                (e.currentTarget as HTMLAnchorElement).style.background = "rgba(157, 0, 255, 0.25)";
                (e.currentTarget as HTMLAnchorElement).style.borderColor = "rgba(157, 0, 255, 0.6)";
              }}
              onMouseLeave={(e) => {
                (e.currentTarget as HTMLAnchorElement).style.background = "rgba(157, 0, 255, 0.15)";
                (e.currentTarget as HTMLAnchorElement).style.borderColor = "rgba(157, 0, 255, 0.35)";
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
          className="absolute bottom-10 left-1/2 -translate-x-1/2 flex flex-col items-center transition-colors"
          style={{ color: "rgba(0, 229, 255, 0.5)", animation: "bounce 2s ease-in-out infinite" }}
        >
          <span
            className="text-xs uppercase tracking-widest mb-1"
            style={{ fontFamily: "'Montserrat', sans-serif", color: "rgba(0, 229, 255, 0.5)" }}
          >
            Scroll
          </span>
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" style={{ color: "#00e5ff" }}>
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 14l-7 7m0 0l-7-7m7 7V3" />
          </svg>
        </div>

      </VideoHero>

      {/* ── Vaults ── */}
      <section
        className="max-w-7xl mx-auto px-6 py-20 space-y-8"
        style={{ background: "#030508" }}
      >
        <div className="flex items-center gap-3 mb-2">
          <div className="h-px flex-1" style={{ background: "linear-gradient(to right, transparent, rgba(0, 229, 255, 0.2), transparent)" }} />
          <div
            className="flex items-center gap-2 text-sm font-semibold"
            style={{ color: "#00e5ff", fontFamily: "'Montserrat', sans-serif" }}
          >
            <span>⬡</span> Alpha Vaults
          </div>
          <div className="h-px flex-1" style={{ background: "linear-gradient(to right, transparent, rgba(0, 229, 255, 0.2), transparent)" }} />
        </div>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          {VAULTS.map((v) => <VaultCard key={v} vault={v} />)}
        </div>
      </section>

    </div>
  );
}
