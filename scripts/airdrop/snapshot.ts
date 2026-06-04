#!/usr/bin/env node
/**
 * Airdrop snapshot generator (M9).
 *
 * Pulls testnet participation data from ON-CHAIN EVENTS (no Supabase), scores
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
 * SAFETY: this script READS only (eth_getLogs). It writes nothing on-chain.
 * The output is reviewed before any MerkleDistributor deploy.
 */

import * as fs from "fs";
import * as path from "path";
import {
  createPublicClient,
  http,
  formatUnits,
  keccak256,
  encodePacked,
  encodeAbiParameters,
  parseAbiItem,
  getAddress,
  zeroAddress,
  type PublicClient,
  type AbiEvent,
} from "viem";

// ─── Configuration ──────────────────────────────────────────────────────
//
// DATA SOURCE (2026-06-04 rewrite): eligibility is derived ENTIRELY from
// on-chain events — the prior Supabase tables (faucet_drips / vault_share_events
// / provider_stats) were wiped, so this no longer depends on them. The three
// tracks now scan:
//   1. faucet  → ERC-20 Transfer mints (from == 0x0) on the 4 testnet mock tokens
//   2. deposit → ERC-4626 Deposit events on the 4 vaults (summed shares per owner)
//   3. quant   → SignalScored events on EpochScoring (summed accuracy per provider)
//
// ⚠️ VERIFY BEFORE USE: this is a run-once tool whose JSON output is reviewed
//    before any MerkleDistributor deploy (see header). Set SNAPSHOT_FROM_BLOCK to
//    the earliest relevant contract-deploy block and SNAPSHOT_TO_BLOCK to the
//    snapshot block, then run `npx tsx scripts/airdrop/snapshot.ts` and sanity-
//    check the printed counts + total before deploying.

const HYPEREVM_RPC = process.env.HYPEREVM_RPC_URL ?? "https://rpc.hyperliquid-testnet.xyz/evm";

// Block window to scan. FROM must cover the earliest contract deploy you want to
// credit; TO is the snapshot block (defaults to latest at run time).
const SNAPSHOT_FROM_BLOCK = BigInt(process.env.SNAPSHOT_FROM_BLOCK ?? "0");
const SNAPSHOT_TO_BLOCK = process.env.SNAPSHOT_TO_BLOCK ? BigInt(process.env.SNAPSHOT_TO_BLOCK) : undefined;
const MAX_BLOCK_RANGE = BigInt(process.env.MAX_BLOCK_RANGE ?? "1000"); // public HyperEVM eth_getLogs cap
const CHUNK_DELAY_MS = Number(process.env.CHUNK_DELAY_MS ?? "250");

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

// Canonical 2026-06-04 signal stack (EpochScoring redeployed; the prior
// 0xDcB2a366 was a dead 2026-05-25 deploy).
const EPOCH_SCORING = "0x659569A6f195698745779E59fef88e3B5Fe0484A";

// Testnet mock ERC-20s the faucet mints (Track 1 = anyone who minted any of them).
const FAUCET_TOKENS = {
  WBTC: "0x08890A5B7D6D157Da65C04C19150fF7d124eaE40",
  WETH: "0x80F727AF3f7932718fEb25FC28818Ad103040BD2",
  WSOL: "0x2b9d5bBD8C5FEfc71E985d993C13db2770469972",
  WXRP: "0xe1Fe75622Bd5D962c72c1D0A621e5fa6656a4371",
} as const;

// ─── On-chain log scanning (replaces Supabase) ───────────────────────────

const client: PublicClient = createPublicClient({ transport: http(HYPEREVM_RPC) });

const EV_TRANSFER = parseAbiItem(
  "event Transfer(address indexed from, address indexed to, uint256 value)",
) as AbiEvent;
const EV_DEPOSIT = parseAbiItem(
  "event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares)",
) as AbiEvent;
const EV_SIGNAL_SCORED = parseAbiItem(
  "event SignalScored(address indexed provider, uint256 accuracy, uint256 finalScore, uint256 rank)",
) as AbiEvent;

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/**
 * eth_getLogs over [from, to] in MAX_BLOCK_RANGE chunks, with patient retries on
 * the public RPC's rate-limit (-32005). Mirrors the engine indexer's proven
 * pattern. `args` filters indexed topics (e.g. { from: zeroAddress } for mints).
 */
async function getLogsChunked(
  address: `0x${string}`,
  event: AbiEvent,
  args: Record<string, unknown> | undefined,
  fromBlock: bigint,
  toBlock: bigint,
): Promise<any[]> {
  const out: any[] = [];
  for (let start = fromBlock; start <= toBlock; start += MAX_BLOCK_RANGE) {
    const end = start + MAX_BLOCK_RANGE - 1n > toBlock ? toBlock : start + MAX_BLOCK_RANGE - 1n;
    let attempt = 0;
    for (;;) {
      try {
        const logs = await client.getLogs({ address, event, args: args as any, fromBlock: start, toBlock: end });
        out.push(...logs);
        break;
      } catch (err: any) {
        attempt++;
        const msg = String(err?.message ?? err);
        const rateLimited = msg.includes("-32005") || msg.toLowerCase().includes("rate");
        if (attempt > 20 || !rateLimited) throw err;
        await sleep(Math.min(30_000, 500 * 2 ** attempt));
      }
    }
    if (CHUNK_DELAY_MS) await sleep(CHUNK_DELAY_MS);
  }
  return out;
}

async function resolveToBlock(): Promise<bigint> {
  return SNAPSHOT_TO_BLOCK ?? (await client.getBlockNumber());
}

// ─── Track 1: faucet users (on-chain ERC-20 mint events) ─────────────────

async function gatherFaucetUsers(): Promise<Map<string, number>> {
  // Anyone who minted any of the 4 testnet mock tokens (Transfer from 0x0).
  // Flat score = 1 per unique wallet.
  const score = new Map<string, number>();
  const to = await resolveToBlock();
  for (const [sym, addr] of Object.entries(FAUCET_TOKENS)) {
    const logs = await getLogsChunked(getAddress(addr), EV_TRANSFER, { from: zeroAddress }, SNAPSHOT_FROM_BLOCK, to);
    for (const lg of logs) {
      const recipient = (lg.args?.to as string | undefined)?.toLowerCase();
      if (recipient && recipient !== zeroAddress) score.set(recipient, 1);
    }
    console.log(`    faucet ${sym}: ${logs.length} mint logs`);
  }
  return score;
}

// ─── Track 2: vault depositors (on-chain ERC-4626 Deposit events) ────────

async function gatherDepositors(): Promise<Map<string, bigint>> {
  // Score = total shares minted to the owner across all 4 vaults (summed over
  // every Deposit). Simple + sybil-resistant-enough; a future version could
  // weight by time-in-vault or peak balance.
  const score = new Map<string, bigint>();
  const to = await resolveToBlock();
  for (const [sym, addr] of Object.entries(VAULTS)) {
    const logs = await getLogsChunked(getAddress(addr), EV_DEPOSIT, undefined, SNAPSHOT_FROM_BLOCK, to);
    for (const lg of logs) {
      const owner = (lg.args?.owner as string | undefined)?.toLowerCase();
      const shares = (lg.args?.shares as bigint | undefined) ?? 0n;
      if (owner) score.set(owner, (score.get(owner) ?? 0n) + shares);
    }
    console.log(`    vault ${sym}: ${logs.length} deposit logs`);
  }
  return score;
}

// ─── Track 3: quant contributors (on-chain SignalScored events) ──────────

async function gatherQuants(): Promise<Map<string, bigint>> {
  // Score = summed accuracy (bps) across all scored signals, per provider —
  // read from EpochScoring's SignalScored events (same source the indexer uses).
  const score = new Map<string, bigint>();
  const to = await resolveToBlock();
  const logs = await getLogsChunked(getAddress(EPOCH_SCORING), EV_SIGNAL_SCORED, undefined, SNAPSHOT_FROM_BLOCK, to);
  for (const lg of logs) {
    const provider = (lg.args?.provider as string | undefined)?.toLowerCase();
    const accuracy = (lg.args?.accuracy as bigint | undefined) ?? 0n;
    if (provider) score.set(provider, (score.get(provider) ?? 0n) + accuracy);
  }
  console.log(`    SignalScored: ${logs.length} logs`);
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
 * Build a Merkle tree whose leaves match MerkleDistributor.sol exactly:
 *   leaf = keccak256(bytes.concat(keccak256(abi.encode(index, account, amount))))
 * i.e. double-hashed (audit M-8), ABI-encoded over (uint256 index, address
 * account, uint256 amount). `index` is the wallet's position in the sorted
 * wallet list — the same value passed to claim(index, account, amount, proof).
 *
 * Returns root + per-wallet proofs + per-wallet index. Internal nodes are
 * sorted-pair hashed to match OpenZeppelin MerkleProof.verify.
 *
 * Note: production deploys should use @openzeppelin/merkle-tree which handles
 * edge cases (uneven trees, sorting, duplicate detection). This is a reference
 * implementation for review; replace with the library before a real
 * distributor goes live.
 */
function buildMerkleTree(allocations: Map<string, bigint>): {
  root: `0x${string}`;
  proofs: Map<string, `0x${string}`[]>;
  indices: Map<string, number>;
} {
  const wallets = [...allocations.keys()].sort();
  const indices = new Map<string, number>();
  wallets.forEach((w, i) => indices.set(w, i));
  const leaves = wallets.map((w, i) => {
    const inner = keccak256(
      encodeAbiParameters(
        [{ type: "uint256" }, { type: "address" }, { type: "uint256" }],
        [BigInt(i), w as `0x${string}`, allocations.get(w)!]
      )
    );
    // Double-hash: keccak256 of the 32-byte inner hash (== bytes.concat(inner)).
    return keccak256(inner);
  });

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

  return { root, proofs, indices };
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

  // Gather scores SEQUENTIALLY — three parallel chunked scans would thrash the
  // rate-limited public RPC. Each prints its per-source log counts.
  console.log(`Scanning on-chain events from block ${SNAPSHOT_FROM_BLOCK} (set SNAPSHOT_FROM_BLOCK/TO_BLOCK to bound)...`);
  const faucetScores = await gatherFaucetUsers();
  const depositorScores = await gatherDepositors();
  const quantScores = await gatherQuants();

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
  const { root, proofs, indices } = buildMerkleTree(totals);
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
      // index is the value passed to MerkleDistributor.claim(index, ...).
      index: indices.get(wallet)!,
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
