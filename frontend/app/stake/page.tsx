"use client";

import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { STAKING_ABI, addresses } from "@/lib/contracts";
import { useState, useEffect, useMemo } from "react";

const MAX_LOCK_SECONDS = 730 * 24 * 60 * 60;
const MIN_LOCK_SECONDS = 7 * 24 * 60 * 60;

function fmtZENT(raw: bigint): string {
  const v = Number(raw / 10n ** 18n);
  return v.toLocaleString(undefined, { maximumFractionDigits: 2 });
}

function fmtVeZENT(raw: bigint): string {
  const v = Number(raw / 10n ** 18n);
  return v.toFixed(4);
}

function Countdown({ targetTimestamp }: { targetTimestamp: bigint }) {
  const [remaining, setRemaining] = useState("");
  useEffect(() => {
    function tick() {
      const now = Math.floor(Date.now() / 1000);
      const diff = Number(targetTimestamp) - now;
      if (diff <= 0) { setRemaining("Unlocked"); return; }
      const d = Math.floor(diff / 86400);
      const h = Math.floor((diff % 86400) / 3600);
      const m = Math.floor((diff % 3600) / 60);
      setRemaining(`${d}d ${h}h ${m}m`);
    }
    tick();
    const id = setInterval(tick, 30_000);
    return () => clearInterval(id);
  }, [targetTimestamp]);
  return <span>{remaining}</span>;
}

function LockBar({ lockEnd, lockStart }: { lockEnd: bigint; lockStart: bigint }) {
  const [pct, setPct] = useState(0);
  useEffect(() => {
    function tick() {
      const now = Math.floor(Date.now() / 1000);
      const total = Number(lockEnd) - Number(lockStart);
      const elapsed = now - Number(lockStart);
      setPct(Math.min(100, Math.max(0, Math.round((elapsed / total) * 100))));
    }
    tick();
    const id = setInterval(tick, 30_000);
    return () => clearInterval(id);
  }, [lockEnd, lockStart]);
  return (
    <div>
      <div className="flex justify-between text-xs text-white/50 mb-1">
        <span>Lock progress</span>
        <span>{pct}%</span>
      </div>
      <div className="h-2 rounded-full bg-white/10 overflow-hidden">
        <div className="h-full bg-amber-500 rounded-full transition-all" style={{ width: `${pct}%` }} />
      </div>
    </div>
  );
}

export default function StakePage() {
  const { address, isConnected } = useAccount();

  const totalStaked = useReadContract({ address: addresses.ZENTStaking, abi: STAKING_ABI, functionName: "totalStaked" } as any);
  const minStake = useReadContract({ address: addresses.ZENTStaking, abi: STAKING_ABI, functionName: "minStake" } as any);
  const userStaked = useReadContract({ address: addresses.ZENTStaking, abi: STAKING_ABI, functionName: "stakedBalance", args: address ? [address] : undefined, query: { enabled: isConnected } } as any);
  const userVeBalance = useReadContract({ address: addresses.ZENTStaking, abi: STAKING_ABI, functionName: "veBalance", args: address ? [address] : undefined, query: { enabled: isConnected } } as any);
  const userHasAccess = useReadContract({ address: addresses.ZENTStaking, abi: STAKING_ABI, functionName: "hasAccess", args: address ? [address] : undefined, query: { enabled: isConnected } } as any);
  const userLockEnd = useReadContract({ address: addresses.ZENTStaking, abi: STAKING_ABI, functionName: "lockEndOf", args: address ? [address] : undefined, query: { enabled: isConnected } } as any);

  const [stakeAmount, setStakeAmount] = useState("");
  const [lockDays, setLockDays] = useState(365);
  const [isPending, setIsPending] = useState(false);
  const [txHash, setTxHash] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const { writeContract } = useWriteContract();

  // veZENT preview calculator
  const previewVe = useMemo(() => {
    const amt = parseFloat(stakeAmount) * 1e18;
    if (!amt || isNaN(amt)) return "0";
    const remaining = Math.max(0, lockDays * 86400 - Math.floor(Date.now() / 1000));
    const veRaw = (BigInt(Math.floor(amt)) * BigInt(remaining)) / BigInt(MAX_LOCK_SECONDS);
    return (veRaw / 10n ** 18n).toLocaleString();
  }, [stakeAmount, lockDays]);

  const lockDurationSeconds = lockDays * 86400;

  async function handleStake(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setIsPending(true);
    try {
      writeContract({
        address: addresses.ZENTStaking,
        abi: STAKING_ABI,
        functionName: "stake",
        args: [BigInt(Math.floor(parseFloat(stakeAmount) * 1e18)), BigInt(lockDurationSeconds)],
      } as any);
    } catch (err: any) {
      setError(err.message ?? "Transaction failed");
      setIsPending(false);
    }
  }

  if (!isConnected) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="text-center">
          <h1 className="text-2xl font-bold text-white mb-4">ZENT Staking</h1>
          <p className="text-white/50">Connect your wallet to stake ZENT</p>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen">
      <header className="border-b border-white/10 bg-[#0d0d14]/80 backdrop-blur-sm sticky top-0 z-10">
        <div className="mx-auto max-w-7xl px-6 py-4">
          <h1 className="text-2xl font-bold text-white">ZENT Staking</h1>
          <p className="text-xs text-white/40 mt-0.5">Lock ZENT to earn veZENT and access Alpha Vaults</p>
        </div>
      </header>

      <main className="mx-auto max-w-4xl px-6 py-10 space-y-8">
        {/* Protocol Stats */}
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          {[
            { label: "Total ZENT Staked", value: totalStaked.data !== undefined ? fmtZENT(totalStaked.data as bigint) : "—" },
            { label: "Min. Stake Required", value: minStake.data !== undefined ? fmtZENT(minStake.data as bigint) : "—" },
            { label: "Your veZENT Balance", value: userVeBalance.data !== undefined ? fmtVeZENT(userVeBalance.data as bigint) : "—", accent: true },
          ].map(({ label, value, accent }) => (
            <div key={label} className="rounded-2xl border border-white/10 bg-white/5 p-5">
              <div className="text-xs text-white/40 mb-1 uppercase tracking-wider">{label}</div>
              <div className={`text-2xl font-bold font-mono ${accent ? "text-amber-400" : "text-white"}`}>{value}</div>
            </div>
          ))}
        </div>

        {/* Your Position */}
        <div className="rounded-2xl border border-white/10 bg-white/5 p-6">
          <h2 className="text-lg font-semibold text-white mb-4">Your Position</h2>
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
            <div>
              <div className="text-xs text-white/40 mb-1">Staked ZENT</div>
              <div className="font-mono font-medium text-white">{userStaked.data !== undefined ? fmtZENT(userStaked.data as bigint) : "—"}</div>
            </div>
            <div>
              <div className="text-xs text-white/40 mb-1">Lock Expires</div>
              <div className="font-mono font-medium text-white">
                {userLockEnd.data !== undefined && Number(userLockEnd.data) > 0
                  ? <Countdown targetTimestamp={userLockEnd.data as bigint} />
                  : "No active lock"}
              </div>
            </div>
            <div>
              <div className="text-xs text-white/40 mb-1">Vault Access</div>
              <div className={`font-semibold ${(userHasAccess.data as boolean) ? "text-emerald-400" : "text-red-400"}`}>
                {(userHasAccess.data as boolean) ? "Granted" : "Denied"}
              </div>
            </div>
            <div>
              <div className="text-xs text-white/40 mb-1">veZENT</div>
              <div className="font-mono font-medium text-amber-400">
                {userVeBalance.data !== undefined ? fmtVeZENT(userVeBalance.data as bigint) : "—"}
              </div>
            </div>
          </div>
          {userLockEnd.data !== undefined && Number(userLockEnd.data) > 0 && (
            <div className="mt-4">
              <LockBar lockEnd={userLockEnd.data as bigint} lockStart={BigInt(Math.floor(Date.now() / 1000) - 1)} />
            </div>
          )}
        </div>

        {/* Stake Form */}
        <div className="rounded-2xl border border-amber-500/20 bg-amber-500/5 p-6">
          <h2 className="text-lg font-semibold text-amber-400 mb-1">Stake ZENT</h2>
          <p className="text-xs text-white/40 mb-6">Lock ZENT for up to 730 days. Longer locks = more veZENT = more governance power.</p>

          <form onSubmit={handleStake} className="space-y-5">
            <div>
              <label className="mb-1.5 block text-xs font-medium text-white/60 uppercase tracking-wider">Amount (ZENT)</label>
              <input
                type="number"
                step="any"
                min="0"
                placeholder="1000"
                value={stakeAmount}
                onChange={(e) => setStakeAmount(e.target.value)}
                className="w-full rounded-lg border border-slate-700 bg-slate-900 px-3 py-2.5 font-mono text-white outline-none focus:border-amber-500 focus:ring-1 focus:ring-amber-500"
              />
            </div>

            <div>
              <label className="mb-1.5 block text-xs font-medium text-white/60 uppercase tracking-wider">
                Lock Duration: <span className="text-amber-400">{lockDays} days</span>
              </label>
              <input
                type="range"
                min={7}
                max={730}
                value={lockDays}
                onChange={(e) => setLockDays(Number(e.target.value))}
                className="w-full accent-amber-500"
              />
              <div className="flex justify-between text-xs text-white/40 mt-1">
                <span>7 days</span>
                <span>730 days</span>
              </div>
            </div>

            {stakeAmount && parseFloat(stakeAmount) > 0 && (
              <div className="rounded-lg bg-slate-900 border border-slate-700 p-4 space-y-1">
                <div className="flex justify-between text-sm">
                  <span className="text-white/50">veZENT you will receive</span>
                  <span className="font-mono text-amber-400 font-medium">{previewVe}</span>
                </div>
                <div className="flex justify-between text-sm">
                  <span className="text-white/50">Vault access</span>
                  <span className="text-emerald-400 font-medium">Unlocked when active</span>
                </div>
              </div>
            )}

            {error && (
              <div className="rounded-lg border border-red-800 bg-red-950/50 px-4 py-3 text-sm text-red-400">
                {error}
              </div>
            )}

            <button
              type="submit"
              disabled={isPending || !stakeAmount || parseFloat(stakeAmount) <= 0}
              className="w-full rounded-lg bg-amber-500 hover:bg-amber-400 disabled:opacity-50 disabled:cursor-not-allowed text-black font-bold py-3 transition-colors"
            >
              {isPending ? "Confirm in wallet…" : "Stake ZENT"}
            </button>
          </form>
        </div>

        {/* Contract link */}
        <div className="text-center">
          <a
            href={`https://hypurrscan.io/address/${addresses.ZENTStaking}`}
            target="_blank"
            rel="noopener noreferrer"
            className="text-xs text-blue-400 hover:text-blue-300 hover:underline"
          >
            View ZENTStaking on HypurrScan →
          </a>
        </div>
      </main>
    </div>
  );
}
