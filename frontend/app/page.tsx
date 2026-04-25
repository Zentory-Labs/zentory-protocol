"use client";

import { useAccount, useBalance, useReadContract, useConnect } from "wagmi";
import { addresses, ZENT_ABI, VAULT_ABI, STAKING_ABI, vaultMeta } from "@/lib/contracts";

const VAULTS = [addresses.zETH, addresses.zBTC, addresses.zXRP, addresses.zSOL] as const;

function formatUnits(value: bigint, decimals: number): string {
  if (value === 0n) return "0";
  const divisor = 10n ** BigInt(decimals);
  const integer = value / divisor;
  const fractional = value % divisor;
  const fractionalStr = fractional.toString().padStart(decimals, "0").slice(0, 4);
  return `${integer}.${fractionalStr}`;
}

function shorten(addr: string): string {
  return `${addr.slice(0, 6)}...${addr.slice(-4)}`;
}

// ─── Wallet Connect Button ────────────────────────────────────────────────────
function WalletButton() {
  const { address, isConnected } = useAccount();
  const { connect, connectors } = useConnect();

  if (isConnected && address) {
    return (
      <div className="flex items-center gap-2 rounded-full border border-white/20 bg-white/5 px-4 py-2">
        <div className="h-2 w-2 rounded-full bg-emerald-400" />
        <span className="font-mono text-sm text-white">{shorten(address)}</span>
      </div>
    );
  }

  async function handleConnect() {
    if (connectors.length === 0) {
      alert("No wallet detected. Make sure Rabby or MetaMask is installed.");
      return;
    }
    // Try each connector until one works (Rabby, MetaMask, WalletConnect...)
    for (const connector of connectors) {
      try {
        await connect({ connector });
        return;
      } catch {
        // Try next connector
      }
    }
  }

  return (
    <button
      onClick={handleConnect}
      className="rounded-full bg-amber-500 hover:bg-amber-400 text-black font-semibold px-5 py-2 text-sm transition-colors"
    >
      Connect Wallet
    </button>
  );
}

// ─── Vault Card ───────────────────────────────────────────────────────────────
function VaultCard({ vault }: { vault: typeof VAULTS[number] }) {
  const meta = vaultMeta[vault];

  const totalAssets = useReadContract({
    address: vault,
    abi: VAULT_ABI,
    functionName: "totalAssets" as any,
  } as any);

  const totalSupply = useReadContract({
    address: vault,
    abi: VAULT_ABI,
    functionName: "totalSupply" as any,
  } as any);

  const navPerShare = useReadContract({
    address: vault,
    abi: VAULT_ABI,
    functionName: "getNavPerShare" as any,
  } as any);

  const accrued = useReadContract({
    address: vault,
    abi: VAULT_ABI,
    functionName: "performanceFeeAccrued" as any,
  } as any);

  const tvl = (totalAssets.data as bigint) ?? 0n;
  const tvlFormatted = Number(tvl / 10n ** 18n).toLocaleString(undefined, { maximumFractionDigits: 4 });

  return (
    <div className="rounded-2xl border border-white/10 bg-white/5 p-5 hover:border-white/20 transition-colors">
      <div className="flex items-center gap-3 mb-4">
        <div
          className="h-10 w-10 rounded-full flex items-center justify-center text-sm font-bold"
          style={{
            background: meta.color + "22",
            color: meta.color,
            border: `1px solid ${meta.color}44`,
          }}
        >
          {meta.asset}
        </div>
        <div>
          <div className="font-semibold text-white">{meta.name}</div>
          <div className="text-xs text-white/40">{meta.symbol}</div>
        </div>
      </div>

      <div className="space-y-2">
        <div className="flex justify-between text-sm">
          <span className="text-white/50">TVL</span>
          <span className="font-mono font-medium text-white">
            {totalAssets.isLoading ? "—" : `${tvlFormatted} ${meta.asset}`}
          </span>
        </div>
        <div className="flex justify-between text-sm">
          <span className="text-white/50">NAV / Share</span>
          <span className="font-mono font-medium text-white">
            {navPerShare.isLoading ? "—" : Number((navPerShare.data as bigint) ?? 0n / 10n ** 18n).toFixed(6)}
          </span>
        </div>
        <div className="flex justify-between text-sm">
          <span className="text-white/50">Accrued Fees</span>
          <span className="font-mono font-medium text-amber-400">
            {accrued.isLoading ? "—" : Number((accrued.data as bigint ?? 0n) / 10n ** 18n).toFixed(6)}
          </span>
        </div>
      </div>

      <div className="mt-4 pt-4 border-t border-white/10">
        <a
          href={`https://hypurrscan.io/address/${vault}`}
          target="_blank"
          rel="noopener noreferrer"
          className="text-xs text-blue-400 hover:text-blue-300 hover:underline"
        >
          View on Explorer →
        </a>
      </div>
    </div>
  );
}

// ─── Staking Panel ────────────────────────────────────────────────────────────
function StakingPanel() {
  const { address, isConnected } = useAccount();

  const totalStaked = useReadContract({
    address: addresses.ZENTStaking,
    abi: STAKING_ABI,
    functionName: "totalStaked" as any,
  } as any);

  const minStake = useReadContract({
    address: addresses.ZENTStaking,
    abi: STAKING_ABI,
    functionName: "minStake" as any,
  } as any);

  const userStaked = useReadContract({
    address: addresses.ZENTStaking,
    abi: STAKING_ABI,
    functionName: "stakedBalance" as any,
    args: address ? [address] : undefined,
    query: { enabled: isConnected },
  } as any);

  const userVeBalance = useReadContract({
    address: addresses.ZENTStaking,
    abi: STAKING_ABI,
    functionName: "veBalance" as any,
    args: address ? [address] : undefined,
    query: { enabled: isConnected },
  } as any);

  const hasAccess = useReadContract({
    address: addresses.ZENTStaking,
    abi: STAKING_ABI,
    functionName: "hasAccess" as any,
    args: address ? [address] : undefined,
    query: { enabled: isConnected },
  } as any);

  return (
    <div className="rounded-2xl border border-white/10 bg-white/5 p-5">
      <h2 className="text-lg font-semibold text-white mb-4">ZENT Staking</h2>

      <div className="space-y-3">
        <div className="flex justify-between text-sm">
          <span className="text-white/50">Total ZENT Staked</span>
          <span className="font-mono font-medium text-white">
            {totalStaked.isLoading ? "—" : Number((totalStaked.data as bigint ?? 0n) / 10n ** 18n).toLocaleString()}
          </span>
        </div>
        <div className="flex justify-between text-sm">
          <span className="text-white/50">Min. Stake Required</span>
          <span className="font-mono font-medium text-white">
            {minStake.isLoading ? "—" : Number((minStake.data as bigint ?? 0n) / 10n ** 18n).toLocaleString()}
          </span>
        </div>

        {isConnected ? (
          <div className="border-t border-white/10 pt-3 mt-3 space-y-2">
            <div className="flex justify-between text-sm">
              <span className="text-white/50">Your Staked ZENT</span>
              <span className="font-mono font-medium text-white">
                {userStaked.isLoading ? "—" : Number((userStaked.data as bigint ?? 0n) / 10n ** 18n).toLocaleString()}
              </span>
            </div>
            <div className="flex justify-between text-sm">
              <span className="text-white/50">Your veZENT</span>
              <span className="font-mono font-medium text-amber-400">
                {userVeBalance.isLoading ? "—" : Number((userVeBalance.data as bigint ?? 0n) / 10n ** 18n).toFixed(2)}
              </span>
            </div>
            <div className="flex justify-between text-sm">
              <span className="text-white/50">Vault Access</span>
              <span className={`font-medium ${(hasAccess.data as boolean) ? "text-emerald-400" : "text-red-400"}`}>
                {hasAccess.isLoading ? "—" : (hasAccess.data as boolean) ? "Granted" : "Denied"}
              </span>
            </div>
          </div>
        ) : (
          <p className="text-xs text-white/40 mt-2">Connect wallet to view your position</p>
        )}
      </div>

      <div className="mt-4 pt-4 border-t border-white/10">
        <a
          href={`https://hypurrscan.io/address/${addresses.ZENTStaking}`}
          target="_blank"
          rel="noopener noreferrer"
          className="text-xs text-blue-400 hover:text-blue-300 hover:underline"
        >
          View on Explorer →
        </a>
      </div>
    </div>
  );
}

// ─── Governance Panel ──────────────────────────────────────────────────────────
function GovernancePanel() {
  return (
    <div className="rounded-2xl border border-white/10 bg-white/5 p-5">
      <h2 className="text-lg font-semibold text-white mb-4">Governance</h2>

      <div className="space-y-3">
        {[
          { label: "Timelock", addr: addresses.Timelock },
          { label: "Zentroller", addr: addresses.Zentroller },
          { label: "ZentGovernor", addr: addresses.ZentGovernor },
        ].map(({ label, addr }) => (
          <div key={label} className="flex justify-between text-sm">
            <span className="text-white/50">{label}</span>
            <a
              href={`https://hypurrscan.io/address/${addr}`}
              target="_blank"
              rel="noopener noreferrer"
              className="font-mono text-xs text-blue-400 hover:text-blue-300"
            >
              {shorten(addr)}
            </a>
          </div>
        ))}
      </div>

      <div className="mt-4 pt-4 border-t border-white/10">
        <a
          href={`https://hypurrscan.io/address/${addresses.ZentGovernor}`}
          target="_blank"
          rel="noopener noreferrer"
          className="text-xs text-blue-400 hover:text-blue-300 hover:underline"
        >
          View Governor on Explorer →
        </a>
      </div>
    </div>
  );
}

// ─── Main Page ────────────────────────────────────────────────────────────────
export default function Home() {
  const { address, isConnected } = useAccount();
  const { data: hypeBalance } = useBalance({ address });

  const zenTotalSupply = useReadContract({
    address: addresses.ZENT,
    abi: ZENT_ABI,
    functionName: "totalSupply" as any,
  } as any);

  const zenBalance = useReadContract({
    address: addresses.ZENT,
    abi: ZENT_ABI,
    functionName: "balanceOf" as any,
    args: address ? [address] : undefined,
    query: { enabled: isConnected },
  } as any);

  const zenSupply = (zenTotalSupply.data as bigint) ?? 0n;
  const zenSupplyFormatted = (Number(zenSupply) / 1e27).toFixed(0);

  return (
    <div className="min-h-screen">
      {/* Header */}
      <header className="border-b border-white/10 bg-[#0d0d14]/80 backdrop-blur-sm sticky top-0 z-20">
        <div className="mx-auto max-w-7xl px-6 py-4 flex items-center justify-between">
          <div>
            <h1 className="text-xl font-bold tracking-tight text-white">Zentory Protocol</h1>
            <p className="text-xs text-white/40 mt-0.5">HyperEVM Testnet · Chain 998</p>
          </div>
          <div className="flex items-center gap-4">
            <WalletButton />
            {isConnected && hypeBalance && (
              <div className="hidden sm:flex flex-col items-end">
                <span className="text-xs font-mono text-white">{shorten(address!)}</span>
                <span className="text-xs text-emerald-400">
                  {Number(hypeBalance.value / 10n ** 18n).toFixed(4)} HYPE
                </span>
              </div>
            )}
          </div>
        </div>
      </header>

      <main className="mx-auto max-w-7xl px-6 py-10 space-y-10">
        {/* Protocol Overview */}
        <section>
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
            <div className="rounded-2xl border border-amber-500/20 bg-gradient-to-br from-amber-500/10 to-amber-600/5 p-5">
              <div className="text-amber-400 text-xs font-medium uppercase tracking-wider mb-1">ZENT Token</div>
              <div className="text-2xl font-bold text-white">{zenTotalSupply.isLoading ? "—" : `${zenSupplyFormatted}B`}</div>
              <div className="text-xs text-white/40 mt-1">total supply</div>
              {isConnected && zenBalance.data !== undefined && (
                <div className="mt-3 pt-3 border-t border-white/10">
                  <div className="text-xs text-white/40">Your Balance</div>
                  <div className="text-sm font-mono text-white">
                    {Number((zenBalance.data as bigint) / 10n ** 18n).toLocaleString()} ZENT
                  </div>
                </div>
              )}
            </div>

            <div className="rounded-2xl border border-blue-500/20 bg-gradient-to-br from-blue-500/10 to-blue-600/5 p-5">
              <div className="text-blue-400 text-xs font-medium uppercase tracking-wider mb-1">Network</div>
              <div className="text-2xl font-bold text-white">HyperEVM</div>
              <div className="text-xs text-white/40 mt-1">Chain ID 998 · Testnet</div>
            </div>

            <div className="rounded-2xl border border-emerald-500/20 bg-gradient-to-br from-emerald-500/10 to-emerald-600/5 p-5">
              <div className="text-emerald-400 text-xs font-medium uppercase tracking-wider mb-1">Strategy Executor</div>
              <div className="font-mono text-sm text-white break-all leading-relaxed">
                {shorten(addresses.StrategyExecutor)}
              </div>
              <div className="text-xs text-white/40 mt-1">keeper · risk control</div>
            </div>
          </div>
        </section>

        {/* Alpha Vaults */}
        <section>
          <div className="flex items-center justify-between mb-5">
            <h2 className="text-xl font-semibold text-white">Alpha Vaults</h2>
            <span className="text-xs text-white/40 bg-white/5 border border-white/10 rounded-full px-3 py-1">
              ERC-4626 · Testnet
            </span>
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
            {VAULTS.map((v) => (
              <VaultCard key={v} vault={v} />
            ))}
          </div>
        </section>

        {/* Staking + Governance */}
        <section className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <StakingPanel />
          <GovernancePanel />
        </section>

        {/* Keeper Layer */}
        <section className="rounded-2xl border border-white/10 bg-white/5 p-5">
          <h2 className="text-lg font-semibold text-white mb-4">Keeper Layer</h2>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div>
              <div className="text-xs text-white/40 mb-1">HyperCoreAdapter</div>
              <div className="font-mono text-xs text-white break-all">{addresses.HyperCoreAdapter}</div>
            </div>
            <div>
              <div className="text-xs text-white/40 mb-1">StrategyExecutor</div>
              <div className="font-mono text-xs text-white break-all">{addresses.StrategyExecutor}</div>
            </div>
          </div>
          <div className="mt-4 pt-4 border-t border-white/10 flex gap-6">
            <a
              href="https://hypurrscan.io"
              target="_blank"
              rel="noopener noreferrer"
              className="text-xs text-blue-400 hover:text-blue-300 hover:underline"
            >
              HypurrScan Explorer →
            </a>
            <a
              href="/signals"
              className="text-xs text-amber-400 hover:text-amber-300 hover:underline"
            >
              Signal Dashboard →
            </a>
          </div>
        </section>

        {/* Post-Deploy Checklist */}
        <section className="rounded-2xl border border-amber-500/20 bg-amber-500/5 p-5">
          <h2 className="text-lg font-semibold text-amber-400 mb-3">Post-Deploy Checklist</h2>
          <ul className="space-y-2 text-sm text-white/70">
            {[
              "Fund keeper wallet with HYPE for gas",
              "Configure HyperCoreAdapter asset indices per vault",
              "Transfer Timelock admin to multisig",
              "Set ZENTStaking.minStake via governance proposal",
              "Verify vault KEEPER_ROLE assignments on StrategyExecutor",
            ].map((item, i) => (
              <li key={i} className="flex gap-2">
                <span className="text-amber-400">{i + 1}.</span>
                {item}
              </li>
            ))}
          </ul>
        </section>
      </main>
    </div>
  );
}
