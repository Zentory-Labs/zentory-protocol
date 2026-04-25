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
  const colors: Record<string, string> = {
    amber: "from-amber-500/10 to-amber-600/5 border-amber-500/20 text-amber-400",
    blue: "from-blue-500/10 to-blue-600/5 border-blue-500/20 text-blue-400",
    emerald: "from-emerald-500/10 to-emerald-600/5 border-emerald-500/20 text-emerald-400",
    violet: "from-violet-500/10 to-violet-600/5 border-violet-500/20 text-violet-400",
  };
  const c = colors[accent];
  return (
    <div className={`rounded-2xl border bg-gradient-to-br ${c} p-5 flex-1 min-w-0`}>
      <div className="text-xs font-medium uppercase tracking-wider opacity-70 mb-1">{label}</div>
      <div className="text-2xl font-bold text-white truncate">{value}</div>
      {sub && <div className="text-xs text-white/40 mt-1">{sub}</div>}
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
    <div className="group relative rounded-2xl border border-white/10 bg-white/5 p-5 hover:border-white/20 transition-all duration-300 hover:-translate-y-0.5">
      {/* Asset badge */}
      <div className="flex items-center gap-3 mb-4">
        <div
          className="h-11 w-11 rounded-xl flex items-center justify-center text-sm font-bold shadow-lg"
          style={{
            background: `linear-gradient(135deg, ${meta.color}33, ${meta.color}11)`,
            color: meta.color,
            border: `1px solid ${meta.color}44`,
          }}
        >
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

      <div className="mt-4 pt-4 border-t border-white/10">
        <a
          href={`https://hypurrscan.io/address/${vault}`}
          target="_blank"
          rel="noopener noreferrer"
          className="inline-flex items-center gap-1 text-xs text-blue-400/70 hover:text-blue-400 transition-colors"
        >
          View on Explorer
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
    <div className="rounded-2xl border border-white/10 bg-white/5 p-5">
      <div className="flex items-center gap-2 mb-4">
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
        <div className="border-t border-white/10 pt-3 mt-3 space-y-2">
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

      <div className="mt-4 pt-4 border-t border-white/10">
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
    <div className="rounded-2xl border border-white/10 bg-white/5 p-5">
      <div className="flex items-center gap-2 mb-4">
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

      <div className="mt-4 pt-4 border-t border-white/10">
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
    <div className="rounded-2xl border border-white/10 bg-white/5 p-5">
      <div className="flex items-center gap-2 mb-4">
        <div className="h-2 w-2 rounded-full bg-emerald-400" />
        <h2 className="text-sm font-semibold text-white uppercase tracking-wider">Keeper Layer</h2>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <div>
          <div className="text-xs text-white/40 mb-1.5">HyperCoreAdapter</div>
          <div className="font-mono text-xs text-white/70 break-all leading-relaxed">{addresses.HyperCoreAdapter}</div>
        </div>
        <div>
          <div className="text-xs text-white/40 mb-1.5">StrategyExecutor</div>
          <div className="font-mono text-xs text-white/70 break-all leading-relaxed">{addresses.StrategyExecutor}</div>
        </div>
      </div>

      <div className="mt-4 pt-4 border-t border-white/10 flex items-center gap-6">
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
    <div className="rounded-2xl border border-amber-500/20 bg-gradient-to-br from-amber-500/5 to-transparent p-5">
      <h2 className="text-sm font-semibold text-amber-400 uppercase tracking-wider mb-3">Post-Deploy Checklist</h2>
      <ul className="space-y-2">
        {items.map((item, i) => (
          <li key={i} className="flex items-start gap-2.5 text-sm text-white/60">
            <span className="mt-0.5 h-4 w-4 rounded border border-amber-500/40 flex-shrink-0 flex items-center justify-center">
              <span className="text-amber-400 text-xs">{i + 1}</span>
            </span>
            {item}
          </li>
        ))}
      </ul>
    </div>
  );
}

// ─── Main Page ────────────────────────────────────────────────────────────────

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
      <main className="mx-auto max-w-7xl px-6 py-10 space-y-8">

        {/* ── Protocol Hero ── */}
        <section className="relative overflow-hidden rounded-3xl border border-white/10 bg-gradient-to-br from-white/[0.07] to-transparent p-8 sm:p-10">
          {/* Ambient glow */}
          <div className="absolute -top-24 -right-24 h-64 w-64 rounded-full bg-amber-500/5 blur-3xl pointer-events-none" />
          <div className="absolute -bottom-12 -left-12 h-48 w-48 rounded-full bg-blue-500/5 blur-3xl pointer-events-none" />

          <div className="relative">
            <div className="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-6">
              <div>
                <div className="inline-flex items-center gap-2 rounded-full border border-amber-500/30 bg-amber-500/10 px-3 py-1 text-xs text-amber-400 font-medium mb-4">
                  <div className="h-1.5 w-1.5 rounded-full bg-amber-400 animate-pulse" />
                  HyperEVM Testnet · Chain 998
                </div>
                <h1 className="text-4xl sm:text-5xl font-bold text-white tracking-tight">Zentory Protocol</h1>
                <p className="text-white/50 mt-2 text-base">
                  Alpha generation through systematic, AI-driven strategies.
                  <br />ERC-4626 vaults · ZENT governance · HyperCore execution.
                </p>

                {isConnected && hypeBalance && (
                  <div className="mt-4 inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/5 px-4 py-2">
                    <div className="h-2 w-2 rounded-full bg-emerald-400" />
                    <span className="font-mono text-sm text-white">{shorten(address!)}</span>
                    <span className="text-white/40">·</span>
                    <span className="font-mono text-sm text-emerald-400">{Number(hypeBalance.value / 10n ** 18n).toFixed(4)} HYPE</span>
                  </div>
                )}
              </div>

              {/* ZENT Token metric */}
              <div className="flex-shrink-0">
                <div className="text-xs text-white/40 uppercase tracking-wider mb-1">ZENT Total Supply</div>
                <div className="text-4xl font-bold text-white">{zenTotalSupply.isLoading ? "—" : `${zenSupplyFormatted}B`}</div>
                <div className="text-xs text-white/40 mt-1">1,000,000,000 ZENT</div>
                {isConnected && zenBalance.data !== undefined && (
                  <div className="mt-2 text-xs text-white/50">Your balance: <span className="text-amber-400 font-mono">{Number((zenBalance.data as bigint) / 10n ** 18n).toLocaleString()} ZENT</span></div>
                )}
              </div>
            </div>
          </div>
        </section>

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
