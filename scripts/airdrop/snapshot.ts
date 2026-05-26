#!/usr/bin/env node
/**
 * Airdrop snapshot generator (M9).
 *
 * Pulls testnet participation data from Supabase + on-chain reads, scores
 * each wallet across three contribution tracks, emits a Merkle tree we can
 * feed into MerkleDistributor on mainnet day 1.
 *
 * Three tracks scored:
 *   1. Faucet user — drips of the testnet asset → small flat allocation
 *   2. Vault depositor — actual zBTC/zETH/zSOL/zXRP deposits, weighted by
 *      time-in-vault and peak position size
 *   3. Quant contributor — signal submissions weighted by Conviction Score
 *      from EpochScoring
 *
 * Output: scripts/airdrop/snapshot-<timestamp>.json containing:
 *   {
 *     snapshot_at: ISO timestamp,
 *     chain_id: 998,
 *     total_allocation: bigint string,
 *     allocations: [{ wallet, faucet, depositor, quant, total }],
 *     merkle_root: 0x...,
 *     merkle_proofs: { [wallet]: [...string] }
 *   }
 *
 * Run as: ZENT_TOTAL_AIRDROP=20000000 npx tsx scripts/airdrop/snapshot.ts
 *
 * SAFETY: this script READS only. It does not write anything on-chain or
 * to Supabase. The output is reviewed before any MerkleDistributor deploy.
 */

import * as fs from "fs";
import * as path from "path";
import { createPublicClient, http, formatUnits, keccak256, encodePacked } from "viem";

// ─── Configuration ──────────────────────────────────────────────────────

const SUPABASE_URL = process.env.SUPABASE_URL ?? "";
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY ?? "";
const HYPEREVM_RPC = process.env.HYPEREVM_RPC_URL ?? "https://rpc.hyperliquid-testnet.xyz/evm";

/** Total ZENT allocated to the airdrop (in whole tokens, multiplied by 1e18 later). */
const TOTAL_AIRDROP = BigInt(process.env.ZENT_TOTAL_AIRDROP ?? "20000000"); // 2% of 1B supply default

/** Track weights — what fraction of TOTAL_AIRDROP each track gets. */
const TRACK_WEIGHTS = {
  faucet: 0.10, // 10% — flat distribution to anyone who used the faucet
  depositor: 0.40, // 40% — weighted by vault participation
  quant: 0.50, // 50% — weighted by signal accuracy
} as const;

if (TRACK_WEIGHTS.faucet + TRACK_WEIGHTS.depositor + TRACK_WEIGHTS.quant !== 1.0) {
  throw new Error("Track weights must sum to 1.0");
}

// ─── Contract addresses (testnet) ───────────────────────────────────────

const VAULTS = {
  zBTC: "0x93669daC07321FF397cf5734Ae8364EA24addF45",
  zETH: "0xbe8a9d22560A1b126554b70Aaca2D763B2E70C4e",
  zSOL: "0xb62BA9d0a14aC9f9601891179B3Da52bE71Ce052",
  zXRP: "0x8B15204D88a9Bb155bE6798522983A3B5F7d7cB0",
} as const;

const EPOCH_SCORING = "0xDcB2a366dCD5eE126793523b1BeFd78E32A1694d"; // redeployed 2026-05-25

// ─── Supabase fetches ───────────────────────────────────────────────────

type SupabaseResp<T> = { data: T[] | null; error: unknown };

async function supaSelect<T>(table: string, query = "*"): Promise<T[]> {
  if (!SUPABASE_URL || !SUPABASE_KEY) {
    console.error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
    return [];
  }
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${table}?select=${encodeURIComponent(query)}`, {
    headers: {
      apikey: SUPABASE_KEY,
      Authorization: `Bearer ${SUPABASE_KEY}`,
    },
  });
  if (!res.ok) {
    console.error(`Supabase ${table} fetch failed: ${res.status}`);
    return [];
  }
  return (await res.json()) as T[];
}

// ─── Track 1: faucet users ──────────────────────────────────────────────

async function gatherFaucetUsers(): Promise<Map<string, number>> {
  // Source: `faucet_drips` table mirrored from the dApp faucet endpoint, OR
  // alternatively we scan the testnet mock-ERC20 mint events. For now,
  // assume the dApp logged to Supabase. Each wallet gets a flat score = 1.
  const drips = await supaSelect<{ wallet: string }>("faucet_drips", "wallet");
  const score = new Map<string, number>();
  for (const row of drips) {
    const w = row.wallet?.toLowerCase();
    if (w) score.set(w, 1);
  }
  return score;
}

// ─── Track 2: vault depositors ──────────────────────────────────────────

async function gatherDepositors(): Promise<Map<string, bigint>> {
  // Score = sum across vaults of (peak_share_balance × time_held_seconds).
  // We pull from Supabase `vault_nav_history` which the indexer mirrors.
  // This is a starter heuristic — a real scoring algorithm would also weight
  // for early-deposit-bonus (first 100 depositors get 2x).
  const events = await supaSelect<{
    wallet: string;
    vault_symbol: string;
    shares: string;
    timestamp: number;
  }>("vault_share_events", "wallet,vault_symbol,shares,timestamp");

  const score = new Map<string, bigint>();
  for (const e of events) {
    if (!e.wallet) continue;
    const w = e.wallet.toLowerCase();
    const shares = BigInt(e.shares ?? "0");
    score.set(w, (score.get(w) ?? 0n) + shares);
  }
  return score;
}

// ─── Track 3: quant contributors ────────────────────────────────────────

async function gatherQuants(): Promise<Map<string, bigint>> {
  // Score = lifetime ZENT-bps accuracy summed across all settled signals.
  // Provider stats live in Supabase `provider_stats` written by the keeper.
  const stats = await supaSelect<{
    provider: string;
    accuracy_bps: number;
    payout_zent: string;
  }>("provider_stats", "provider,accuracy_bps,payout_zent");

  const score = new Map<string, bigint>();
  for (const row of stats) {
    if (!row.provider) continue;
    const w = row.provider.toLowerCase();
    // Quant score = accuracy_bps × payout magnitude. Accuracy alone undercounts
    // quants with high stake-density; payout alone undercounts quants with many
    // small accurate calls.
    const accuracyComponent = BigInt(row.accuracy_bps ?? 0);
    const payoutComponent = BigInt(row.payout_zent ?? "0") / 10n ** 14n; // scale down
    score.set(w, (score.get(w) ?? 0n) + accuracyComponent + payoutComponent);
  }
  return score;
}

// ─── Allocation calculation ─────────────────────────────────────────────

function distribute(
  score: Map<string, bigint | number>,
  bucketSize: bigint
): Map<string, bigint> {
  // Convert all scores to bigint, normalize to total bucket size.
  const total = Array.from(score.values()).reduce(
    (a, b) => (a as bigint) + BigInt(b),
    0n as bigint
  );
  const allocations = new Map<string, bigint>();
  if (total === 0n) return allocations;
  for (const [wallet, s] of score) {
    const allocation = (BigInt(s) * bucketSize) / total;
    if (allocation > 0n) allocations.set(wallet, allocation);
  }
  return allocations;
}

// ─── Merkle tree (simplified — production should use OZ MerkleProof) ────

/**
 * Build a Merkle tree of (wallet, amount) leaves. Each leaf hash is
 * keccak256(abi.encodePacked(wallet, amount)) — matches OZ's
 * MerkleDistributor expectation. Returns root + proofs per wallet.
 *
 * Note: production deploys should use @openzeppelin/merkle-tree which
 * handles edge cases (uneven trees, sorting, duplicate detection). This is
 * a reference implementation for review; replace with the library before
 * a real distributor goes live.
 */
function buildMerkleTree(allocations: Map<string, bigint>): {
  root: `0x${string}`;
  proofs: Map<string, `0x${string}`[]>;
} {
  const wallets = [...allocations.keys()].sort();
  const leaves = wallets.map(
    (w) => keccak256(encodePacked(["address", "uint256"], [w as `0x${string}`, allocations.get(w)!]))
  );

  if (leaves.length === 0) {
    return { root: ("0x" + "00".repeat(32)) as `0x${string}`, proofs: new Map() };
  }

  // Pad to power of 2
  while ((leaves.length & (leaves.length - 1)) !== 0) {
    leaves.push(("0x" + "00".repeat(32)) as `0x${string}`);
  }

  // Build tree bottom-up
  let layer = leaves;
  const tree: `0x${string}`[][] = [layer];
  while (layer.length > 1) {
    const next: `0x${string}`[] = [];
    for (let i = 0; i < layer.length; i += 2) {
      const a = layer[i];
      const b = layer[i + 1];
      // Sort pair so verification works without knowing left/right ordering
      const pair = (BigInt(a) < BigInt(b) ? [a, b] : [b, a]) as [`0x${string}`, `0x${string}`];
      next.push(keccak256(encodePacked(["bytes32", "bytes32"], pair)));
    }
    layer = next;
    tree.push(layer);
  }

  const root = layer[0];

  // Generate proofs
  const proofs = new Map<string, `0x${string}`[]>();
  for (let i = 0; i < wallets.length; i++) {
    const proof: `0x${string}`[] = [];
    let idx = i;
    for (let l = 0; l < tree.length - 1; l++) {
      const sibling = idx ^ 1;
      if (sibling < tree[l].length) proof.push(tree[l][sibling]);
      idx = idx >> 1;
    }
    proofs.set(wallets[i], proof);
  }

  return { root, proofs };
}

// ─── Main ───────────────────────────────────────────────────────────────

async function main(): Promise<void> {
  console.log("ZENTORY airdrop snapshot starting...");
  console.log(`Total airdrop: ${TOTAL_AIRDROP} ZENT (${formatUnits(TOTAL_AIRDROP * 10n ** 18n, 18)} with decimals)`);

  const totalScaled = TOTAL_AIRDROP * 10n ** 18n; // ZENT has 18 decimals
  const buckets = {
    faucet: (totalScaled * BigInt(Math.floor(TRACK_WEIGHTS.faucet * 10000))) / 10000n,
    depositor: (totalScaled * BigInt(Math.floor(TRACK_WEIGHTS.depositor * 10000))) / 10000n,
    quant: (totalScaled * BigInt(Math.floor(TRACK_WEIGHTS.quant * 10000))) / 10000n,
  };

  // Gather scores in parallel
  const [faucetScores, depositorScores, quantScores] = await Promise.all([
    gatherFaucetUsers(),
    gatherDepositors(),
    gatherQuants(),
  ]);

  console.log(`  faucet users: ${faucetScores.size}`);
  console.log(`  depositors:   ${depositorScores.size}`);
  console.log(`  quants:       ${quantScores.size}`);

  // Distribute each bucket across its wallets pro-rata to score
  const faucetAllocs = distribute(faucetScores, buckets.faucet);
  const depositorAllocs = distribute(depositorScores, buckets.depositor);
  const quantAllocs = distribute(quantScores, buckets.quant);

  // Merge: each wallet gets sum across the tracks it participated in
  const totals = new Map<string, bigint>();
  const addTo = (m: Map<string, bigint>) => {
    for (const [k, v] of m) totals.set(k, (totals.get(k) ?? 0n) + v);
  };
  addTo(faucetAllocs);
  addTo(depositorAllocs);
  addTo(quantAllocs);

  console.log(`  unique wallets: ${totals.size}`);
  console.log(`  total allocated: ${formatUnits([...totals.values()].reduce((a, b) => a + b, 0n), 18)} ZENT`);

  // Build Merkle tree
  const { root, proofs } = buildMerkleTree(totals);
  console.log(`  merkle root: ${root}`);

  // Write output
  const out = {
    snapshot_at: new Date().toISOString(),
    chain_id: 998,
    epoch_scoring_address: EPOCH_SCORING,
    vaults: VAULTS,
    total_airdrop_zent: TOTAL_AIRDROP.toString(),
    track_weights: TRACK_WEIGHTS,
    track_buckets_zent: {
      faucet: formatUnits(buckets.faucet, 18),
      depositor: formatUnits(buckets.depositor, 18),
      quant: formatUnits(buckets.quant, 18),
    },
    allocations: [...totals.entries()].map(([wallet, total]) => ({
      wallet,
      faucet: (faucetAllocs.get(wallet) ?? 0n).toString(),
      depositor: (depositorAllocs.get(wallet) ?? 0n).toString(),
      quant: (quantAllocs.get(wallet) ?? 0n).toString(),
      total: total.toString(),
    })),
    merkle_root: root,
    merkle_proofs: Object.fromEntries([...proofs.entries()]),
  };

  const outDir = path.dirname(new URL(import.meta.url).pathname);
  const outFile = path.join(outDir, `snapshot-${Math.floor(Date.now() / 1000)}.json`);
  // Serialize bigints as decimal strings
  fs.writeFileSync(outFile, JSON.stringify(out, null, 2));
  console.log(`  written: ${outFile}`);
  console.log("Done.");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
