"use client";

import { useAccount, useBalance, useReadContract } from "wagmi";
import { addresses, ZENT_ABI, VAULT_ABI, STAKING_ABI, vaultMeta } from "@/lib/contracts";

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

// ─── Metric Badge ─────────────────────────────────────────────────────────────

function MetricBadge({
  label,
  value,
  sub,
  accent = "amber",
}: {
  label: string;
  value: string;
  sub?: string;
  accent?: "amber" | "blue" | "emerald" | "violet";
}) {
  return (
    <div className="px-4 py-2 rounded-xl bg-gradient-to-br from-white/[0.08] to-white/[0.02] border border-white/10 backdrop-blur-sm text-sm font-medium">
      <span className="text-xs text-white/40 font-medium uppercase tracking-wider mr-2">{label}</span>
      <span className="text-white font-semibold">{value}</span>
      {sub && <span className="text-xs text-white/30 ml-1.5">{sub}</span>}
    </div>
  );
}

// ─── Vault Card ───────────────────────────────────────────────────────────────

function VaultCard({ vault }: { vault: (typeof VAULTS)[number] }) {
  const meta = vaultMeta[vault];

  const totalAssets = useReadContract({ address: vault, abi: VAULT_ABI, functionName: "totalAssets" } as any);
  const navPerShare = useReadContract({ address: vault, abi: VAULT_ABI, functionName: "getNavPerShare" } as any);
  const accrued = useReadContract({ address: vault, abi: VAULT_ABI, functionName: "performanceFeeAccrued" } as any);

  const tvl = (totalAssets.data as bigint) ?? 0n;

  return (
    <div className="glass-card p-6 glass-hover group">
      {/* Asset badge */}
      <div className="flex items-center gap-3 mb-4">
        <div className="w-12 h-12 rounded-xl bg-gradient-to-br from-white/[0.1] to-white/[0.05] border border-white/10 backdrop-blur-sm flex items-center justify-center text-lg font-bold text-white">
          {meta.asset}
        </div>
        <div>
          <div className="font-semibold text-white text-sm">{meta.name}</div>
          <div className="text-xs text-white/40">{meta.symbol}</div>
        </div>
      </div>

      <div className="space-y-2.5">
        {[
          { label: "TVL", value: totalAssets.isLoading ? "—" : `${fmt(tvl)} ${meta.asset}` },
          { label: "NAV / Share", value: navPerShare.isLoading ? "—" : fmt((navPerShare.data as bigint) ?? 0n) },
          { label: "Accrued Fees", value: accrued.isLoading ? "—" : fmt((accrued.data as bigint) ?? 0n), accent: "text-amber-400" },
        ].map(({ label, value, accent }) => (
          <div key={label} className="flex justify-between items-center">
            <span className="text-xs text-white/50">{label}</span>
            <span className={`text-sm font-mono font-medium ${accent ?? "text-white"}`}>{value}</span>
          </div>
        ))}
      </div>

      {/* APY badge */}
      <div className="mt-4 pt-4 border-t border-white/10 flex items-center justify-between">
        <span className="px-3 py-1 rounded-full text-xs font-semibold bg-gradient-to-r from-[#0d80fa] to-[#3b82f6] text-white shadow-lg shadow-blue-500/25">
          APY 12.4%
        </span>
        <a
          href={`https://hypurrscan.io/address/${vault}`}
          target="_blank"
          rel="noopener noreferrer"
          className="inline-flex items-center gap-1 text-xs text-blue-400/70 hover:text-blue-400 transition-colors"
        >
          View
          <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" /></svg>
        </a>
      </div>
    </div>
  );
}

// ─── Staking & Governance ─────────────────────────────────────────────────────

function StakingPanel() {
  const { address, isConnected } = useAccount();

  const totalStaked = useReadContract({ address: addresses.ZENTStaking, abi: STAKING_ABI, functionName: "totalStaked" } as any);
  const minStake = useReadContract({ address: addresses.ZENTStaking, abi: STAKING_ABI, functionName: "minStake" } as any);
  const userStaked = useReadContract({
    address: addresses.ZENTStaking, abi: STAKING_ABI, functionName: "stakedBalance",
    args: address ? [address] : undefined, query: { enabled: !!isConnected },
  } as any);
  const userVe = useReadContract({
    address: addresses.ZENTStaking, abi: STAKING_ABI, functionName: "veBalance",
    args: address ? [address] : undefined, query: { enabled: !!isConnected },
  } as any);
  const hasAccess = useReadContract({
    address: addresses.ZENTStaking, abi: STAKING_ABI, functionName: "hasAccess",
    args: address ? [address] : undefined, query: { enabled: !!isConnected },
  } as any);

  return (
    <div className="glass-card p-8 glass-hover">
      <div className="flex items-center gap-2 mb-6">
        <div className="h-2 w-2 rounded-full bg-amber-400" />
        <h2 className="text-sm font-semibold text-white uppercase tracking-wider">ZENT Staking</h2>
      </div>

      <div className="space-y-3">
        {[
          { label: "Total ZENT Staked", value: totalStaked.isLoading ? "—" : fmt((totalStaked.data as bigint) ?? 0n) },
          { label: "Min. Stake Required", value: minStake.isLoading ? "—" : fmt((minStake.data as bigint) ?? 0n) },
        ].map(({ label, value }) => (
          <div key={label} className="flex justify-between text-sm">
            <span className="text-white/50">{label}</span>
            <span className="font-mono font-medium text-white">{value}</span>
          </div>
        ))}
      </div>

      {isConnected && (
        <div className="border-t border-white/10 pt-4 mt-4 space-y-2">
          {[
            { label: "Your Staked", value: userStaked.isLoading ? "—" : fmt((userStaked.data as bigint) ?? 0n) },
            { label: "veZENT Balance", value: userVe.isLoading ? "—" : fmt((userVe.data as bigint) ?? 0n), accent: "text-amber-400" },
          ].map(({ label, value, accent }) => (
            <div key={label} className="flex justify-between text-sm">
              <span className="text-white/50">{label}</span>
              <span className={`font-mono font-medium ${accent ?? "text-white"}`}>{value}</span>
            </div>
          ))}
          <div className="flex justify-between text-sm">
            <span className="text-white/50">Vault Access</span>
            <span className={`font-medium ${(hasAccess.data as boolean) ? "text-emerald-400" : "text-red-400"}`}>
              {hasAccess.isLoading ? "—" : (hasAccess.data as boolean) ? "Granted" : "Denied"}
            </span>
          </div>
        </div>
      )}

      <div className="mt-6 pt-4 border-t border-white/10">
        <a href={`https://hypurrscan.io/address/${addresses.ZENTStaking}`} target="_blank" rel="noopener noreferrer"
          className="inline-flex items-center gap-1 text-xs text-blue-400/70 hover:text-blue-400 transition-colors">
          View on Explorer
          <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" /></svg>
        </a>
      </div>
    </div>
  );
}

function GovernancePanel() {
  const items = [
    { label: "Timelock", addr: addresses.Timelock },
    { label: "Zentroller", addr: addresses.Zentroller },
    { label: "ZentGovernor", addr: addresses.ZentGovernor },
  ];

  return (
    <div className="glass-card p-8 glass-hover">
      <div className="flex items-center gap-2 mb-6">
        <div className="h-2 w-2 rounded-full bg-blue-400" />
        <h2 className="text-sm font-semibold text-white uppercase tracking-wider">Governance</h2>
      </div>

      <div className="space-y-3">
        {items.map(({ label, addr }) => (
          <div key={label} className="flex justify-between items-center">
            <span className="text-xs text-white/50">{label}</span>
            <a href={`https://hypurrscan.io/address/${addr}`} target="_blank" rel="noopener noreferrer"
              className="font-mono text-xs text-blue-400/70 hover:text-blue-400 transition-colors">
              {shorten(addr)}
            </a>
          </div>
        ))}
      </div>

      <div className="mt-6 pt-4 border-t border-white/10">
        <a href={`https://hypurrscan.io/address/${addresses.ZentGovernor}`} target="_blank" rel="noopener noreferrer"
          className="inline-flex items-center gap-1 text-xs text-blue-400/70 hover:text-blue-400 transition-colors">
          View Governor
          <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" /></svg>
        </a>
      </div>
    </div>
  );
}

// ─── Keeper Panel ─────────────────────────────────────────────────────────────

function KeeperPanel() {
  return (
    <div className="glass-card p-8 glass-hover">
      <div className="flex items-center gap-2 mb-6">
        <div className="h-2 w-2 rounded-full bg-emerald-400" />
        <h2 className="text-sm font-semibold text-white uppercase tracking-wider">Keeper Layer</h2>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-6">
        <div>
          <div className="text-xs text-white/40 mb-1.5 uppercase tracking-wider">HyperCoreAdapter</div>
          <div className="font-mono text-xs text-white/70 break-all leading-relaxed">{addresses.HyperCoreAdapter}</div>
        </div>
        <div>
          <div className="text-xs text-white/40 mb-1.5 uppercase tracking-wider">StrategyExecutor</div>
          <div className="font-mono text-xs text-white/70 break-all leading-relaxed">{addresses.StrategyExecutor}</div>
        </div>
      </div>

      <div className="mt-6 pt-4 border-t border-white/10 flex items-center gap-6">
        <a href="https://hypurrscan.io" target="_blank" rel="noopener noreferrer"
          className="inline-flex items-center gap-1.5 text-xs text-blue-400/70 hover:text-blue-400 transition-colors font-medium">
          HypurrScan
          <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" /></svg>
        </a>
        <a href="/signals"
          className="inline-flex items-center gap-1.5 text-xs text-amber-400/70 hover:text-amber-400 transition-colors font-medium">
          Signal Dashboard
          <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 7l5 5m0 0l-5 5m5-5H6" /></svg>
        </a>
      </div>
    </div>
  );
}

// ─── Checklist ────────────────────────────────────────────────────────────────

function Checklist() {
  const items = [
    "Fund keeper wallet with HYPE for gas",
    "Configure HyperCoreAdapter asset indices per vault",
    "Transfer Timelock admin to multisig",
    "Set ZENTStaking.minStake via governance proposal",
    "Verify vault KEEPER_ROLE assignments on StrategyExecutor",
  ];
  return (
    <div className="rounded-2xl border border-amber-500/20 bg-gradient-to-br from-amber-500/5 to-transparent p-8">
      <h2 className="text-sm font-semibold text-amber-400 uppercase tracking-wider mb-4">Post-Deploy Checklist</h2>
      <ul className="space-y-3">
        {items.map((item, i) => (
          <li key={i} className="flex items-start gap-3 text-sm text-white/60">
            <span className="mt-0.5 h-5 w-5 rounded border border-amber-500/40 flex-shrink-0 flex items-center justify-center">
              <span className="text-amber-400 text-xs font-semibold">{i + 1}</span>
            </span>
            {item}
          </li>
        ))}
      </ul>
    </div>
  );
}

// ─── Main Page ───────────────────────────────────────────────────────────────

export default function Home() {
  const { address, isConnected } = useAccount();
  const { data: hypeBalance } = useBalance({ address });

  const zenTotalSupply = useReadContract({ address: addresses.ZENT, abi: ZENT_ABI, functionName: "totalSupply" } as any);
  const zenBalance = useReadContract({
    address: addresses.ZENT, abi: ZENT_ABI, functionName: "balanceOf",
    args: address ? [address] : undefined, query: { enabled: !!isConnected },
  } as any);

  const zenSupply = (zenTotalSupply.data as bigint) ?? 0n;
  const zenSupplyFormatted = (zenSupply / 10n ** 27n).toString();

  return (
    <div className="min-h-screen">

      {/* ── Protocol Hero ── */}
      <section className="min-h-[85vh] flex items-center justify-center relative overflow-hidden" style={{ background: "#05070c" }}>
        {/* Ambient glow blobs */}
        <div className="absolute top-0 left-1/4 w-96 h-96 bg-[#0d80fa]/10 rounded-full blur-3xl animate-pulse-glow" />
        <div className="absolute bottom-0 right-1/4 w-96 h-96 bg-purple-500/5 rounded-full blur-3xl animate-pulse-glow" style={{ animationDelay: "1s" }} />
        <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[600px] h-[600px] bg-[#f59e0b]/5 rounded-full blur-3xl" />

        {/* Hero card */}
        <div className="relative z-10 w-full max-w-3xl mx-auto px-6 glass-card p-10 md:p-14 text-center">

          {/* Tagline */}
          <p className="uppercase tracking-[0.2em] text-xs text-[#0d80fa] font-medium mb-6 animate-fade-in" style={{ animationDelay: "0ms" }}>
            HyperEVM · Chain 998 · ERC-4626
          </p>

          {/* Main title */}
          <h1 className="text-5xl sm:text-6xl md:text-7xl font-bold mb-4 animate-slide-up" style={{ animationDelay: "100ms" }}>
            <span className="gradient-text">Zentory Token</span>
          </h1>

          {/* Subtitle */}
          <p className="text-white/70 text-lg md:text-xl font-light mb-8 animate-slide-up" style={{ animationDelay: "200ms" }}>
            Alpha generation through systematic, AI-driven strategies.
            <br className="hidden sm:block" />
            ZENT governance · HyperCore execution.
          </p>

          {/* ZENT Supply metric */}
          <div className="mb-10 animate-slide-up" style={{ animationDelay: "250ms" }}>
            <div className="inline-flex flex-col items-center glass-card px-8 py-4">
              <div className="text-xs text-white/40 uppercase tracking-wider mb-1">Total Supply</div>
              <div className="text-3xl font-bold text-white">{zenTotalSupply.isLoading ? "—" : `${zenSupplyFormatted}B`}</div>
              <div className="text-xs text-white/30 mt-1">ZENT</div>
            </div>
          </div>

          {/* CTA Buttons */}
          <div className="flex flex-col sm:flex-row items-center justify-center gap-4 animate-slide-up" style={{ animationDelay: "300ms" }}>
            <a
              href="/stake"
              className="bg-[#0d80fa] hover:bg-[#0d80fa]/90 text-white px-8 py-3 rounded-lg font-semibold shadow-lg shadow-blue-500/25 transition-all duration-300 hover:scale-[1.02]"
            >
              Stake ZENT
            </a>
            <a
              href="https://docs.zentorytoken.xyz"
              target="_blank"
              rel="noopener noreferrer"
              className="border border-white/20 text-white/80 hover:text-white hover:border-white/40 px-8 py-3 rounded-lg font-medium transition-all duration-300 backdrop-blur-sm"
            >
              Read Docs
            </a>
          </div>

          {/* Connected wallet info */}
          {isConnected && hypeBalance && (
            <div className="mt-8 animate-fade-in" style={{ animationDelay: "400ms" }}>
              <div className="inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/5 px-4 py-2">
                <div className="h-2 w-2 rounded-full bg-emerald-400" />
                <span className="font-mono text-sm text-white">{shorten(address!)}</span>
                <span className="text-white/40">·</span>
                <span className="font-mono text-sm text-emerald-400">{Number(hypeBalance.value / 10n ** 18n).toFixed(4)} HYPE</span>
              </div>
            </div>
          )}

          {/* User ZENT balance */}
          {isConnected && zenBalance.data !== undefined && (
            <div className="mt-4 animate-fade-in" style={{ animationDelay: "450ms" }}>
              <span className="text-xs text-white/40">Your balance: </span>
              <span className="text-amber-400 font-mono text-sm">
                {Number((zenBalance.data as bigint) / 10n ** 18n).toLocaleString()} ZENT
              </span>
            </div>
          )}

        </div>
      </section>

      {/* ── Main Content ── */}
      <main className="mx-auto max-w-7xl px-6 py-10 space-y-8">

        {/* ── Vaults ── */}
        <section>
          <div className="flex items-center gap-3 mb-5">
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

        {/* ── Staking + Governance ── */}
        <section className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <StakingPanel />
          <GovernancePanel />
        </section>

        {/* ── Keeper Layer ── */}
        <KeeperPanel />

        {/* ── Checklist ── */}
        <Checklist />

      </main>
    </div>
  );
}
