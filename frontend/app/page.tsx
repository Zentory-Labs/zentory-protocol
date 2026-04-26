"use client";

import { useAccount, useReadContract } from "wagmi";
import { TubesBackground } from "@/components/neon-flow";
import { addresses, ZENT_ABI, VAULT_ABI, STAKING_ABI, vaultMeta } from "@/lib/contracts";
import { useState } from "react";

const VAULTS = [addresses.zETH, addresses.zBTC, addresses.zXRP, addresses.zSOL] as const;

// ─── Helpers ───────────────────────────────────────────────────────────────────

function shorten(addr: string): string {
  return `${addr.slice(0, 6)}...${addr.slice(-4)}`;
}

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
    <div className="glass-card p-5 glass-hover group">
      <div className="flex items-center gap-3 mb-4">
        <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-white/[0.1] to-white/[0.05] border border-white/10 flex items-center justify-center text-sm font-bold text-white">
          {meta.asset}
        </div>
        <div>
          <div className="font-semibold text-white text-sm">{meta.name}</div>
          <div className="text-xs text-white/40">{meta.symbol}</div>
        </div>
      </div>
      <div className="space-y-2">
        {[
          { label: "TVL", value: totalAssets.isLoading ? "—" : fmtUsd(tvl) },
          { label: "NAV / Share", value: navPerShare.isLoading ? "—" : fmt((navPerShare.data as bigint) ?? 0n) },
        ].map(({ label, value }) => (
          <div key={label} className="flex justify-between items-center">
            <span className="text-xs text-white/50">{label}</span>
            <span className="text-sm font-mono font-medium text-white">{value}</span>
          </div>
        ))}
      </div>
      <div className="mt-4 pt-3 border-t border-white/10 flex items-center justify-between">
        <span className="px-2.5 py-1 rounded-full text-xs font-semibold bg-[#0d80fa]/20 text-[#0d80fa] border border-[#0d80fa]/30">
          Live
        </span>
        <a
          href={`https://hypurrscan.io/address/${vault}`}
          target="_blank"
          rel="noopener noreferrer"
          className="inline-flex items-center gap-1 text-xs text-white/40 hover:text-white/70 transition-colors"
        >
          View
          <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" /></svg>
        </a>
      </div>
    </div>
  );
}

// ─── Chain Data Fetcher ───────────────────────────────────────────────────────

function ChainStats() {
  const { address, isConnected } = useAccount();

  const zenTotalSupply = useReadContract({ address: addresses.ZENT, abi: ZENT_ABI, functionName: "totalSupply" } as any);
  const zenBalance = useReadContract({
    address: addresses.ZENT, abi: ZENT_ABI, functionName: "balanceOf",
    args: address ? [address] : undefined, query: { enabled: !!isConnected },
  } as any);
  const totalStaked = useReadContract({ address: addresses.ZENTStaking, abi: STAKING_ABI, functionName: "totalStaked" } as any);

  const zenSupply = (zenTotalSupply.data as bigint) ?? 0n;
  const zenFormatted = Number(zenSupply / 10n ** 27n).toLocaleString(undefined, { maximumFractionDigits: 0 });
  const stakedFormatted = fmt((totalStaked.data as bigint) ?? 0n);

  return (
    <div className="flex flex-wrap justify-center lg:justify-start gap-8 md:gap-12">
      <div className="text-center">
        <div className="text-2xl md:text-3xl font-bold text-white">{zenTotalSupply.isLoading ? "—" : `${zenFormatted}B`}</div>
        <div className="text-xs md:text-sm text-white/60 uppercase tracking-wider">ZENT Supply</div>
      </div>
      <div className="text-center">
        <div className="text-2xl md:text-3xl font-bold text-white">{totalStaked.isLoading ? "—" : stakedFormatted}</div>
        <div className="text-xs md:text-sm text-white/60 uppercase tracking-wider">ZENT Staked</div>
      </div>
      <div className="text-center">
        <div className="text-2xl md:text-3xl font-bold text-amber-400">4</div>
        <div className="text-xs md:text-sm text-white/60 uppercase tracking-wider">Alpha Vaults</div>
      </div>
      {isConnected && zenBalance.data !== undefined && (
        <div className="text-center">
          <div className="text-2xl md:text-3xl font-bold text-white">
            {Number((zenBalance.data as bigint) / 10n ** 18n).toLocaleString()}
          </div>
          <div className="text-xs md:text-sm text-white/60 uppercase tracking-wider">Your ZENT</div>
        </div>
      )}
    </div>
  );
}

// ─── Main Page ───────────────────────────────────────────────────────────────

export default function Home() {
  const { address, isConnected } = useAccount();

  return (
    <div className="w-full overflow-x-hidden">

      {/* ── Premium Hero ── */}
      <TubesBackground
        className="min-h-[100vh] min-h-[100dvh]"
        enableClickInteraction={true}
      >
        <div className="min-h-[100vh] min-h-[100dvh] flex flex-col items-center justify-center px-6 pointer-events-auto max-w-7xl mx-auto">
          <div className="flex flex-col items-center text-center">

            {/* Badge */}
            <div className="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-white/10 backdrop-blur-sm border border-white/20 text-white/90 text-sm font-medium mb-8">
              <span className="w-2 h-2 rounded-full bg-[#0d80fa] animate-pulse" />
              HyperEVM · Chain 998 · ERC-4626
            </div>

            {/* Main headline */}
            <h1 className="text-6xl sm:text-7xl md:text-8xl lg:text-7xl xl:text-9xl font-bold text-white mb-6 tracking-tight leading-none">
              Zentory Protocol
            </h1>

            {/* Subtitle */}
            <p className="text-xl md:text-2xl lg:text-xl xl:text-2xl text-white/90 font-light max-w-2xl mb-6">
              AI-powered algorithmic trading vaults. Alpha generation through systematic strategies.
            </p>
            <p className="text-base md:text-lg text-white/60 max-w-xl font-light mb-12">
              Stake ZENT · Earn yield · Govern the protocol
            </p>

            {/* CTA buttons */}
            <div className="flex flex-col sm:flex-row gap-4 justify-center items-center mb-16">
              <a
                href="/stake"
                className="px-10 py-4 rounded-xl font-semibold bg-[#f59e0b] text-black hover:bg-[#f59e0b]/90 transition-all duration-300 shadow-2xl hover:shadow-[#f59e0b]/30 hover:scale-[1.02] text-base"
              >
                Stake ZENT
              </a>
              <a
                href="/govern"
                className="px-10 py-4 rounded-xl font-semibold bg-white/10 text-white hover:bg-white/20 transition-all duration-300 border border-white/20 backdrop-blur-sm hover:scale-[1.02] text-base"
              >
                Governance
              </a>
              <a
                href="/signals"
                className="px-10 py-4 rounded-xl font-semibold bg-[#0d80fa] text-white hover:bg-[#0d80fa]/90 transition-all duration-300 shadow-2xl hover:shadow-[#0d80fa]/30 hover:scale-[1.02] text-base"
              >
                Signal Dashboard
              </a>
            </div>

            {/* Live stats */}
            <ChainStats />

          </div>
        </div>

        {/* Scroll indicator */}
        <div className="absolute bottom-10 left-1/2 -translate-x-1/2 flex flex-col items-center text-white/50 hover:text-white/80 transition-colors animate-bounce pointer-events-auto">
          <span className="text-xs uppercase tracking-widest mb-1">Scroll</span>
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 14l-7 7m0 0l-7-7m7 7V3" />
          </svg>
        </div>
      </TubesBackground>

      {/* ── Vaults ── */}
      <section className="max-w-7xl mx-auto px-6 py-20 space-y-8">
        <div className="flex items-center gap-3 mb-2">
          <div className="h-px flex-1 bg-gradient-to-r from-transparent via-white/10 to-transparent" />
          <div className="flex items-center gap-2 text-sm font-medium text-white/40">
            <span className="text-amber-400">⬡</span> Alpha Vaults
          </div>
          <div className="h-px flex-1 bg-gradient-to-r from-transparent via-white/10 to-transparent" />
        </div>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          {VAULTS.map((v) => <VaultCard key={v} vault={v} />)}
        </div>
      </section>

    </div>
  );
}
