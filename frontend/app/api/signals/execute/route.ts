import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/utils/supabase/server";
import { privateKeyToAccount } from "viem/accounts";
import { createPublicClient, createWalletClient, http } from "viem";
import { strategyExecutorABI, HYPEREVM_TESTNET } from "@/lib/contracts";
import { addresses } from "@/lib/contracts";

const RPC_URL = process.env.NEXT_PUBLIC_HYPEREVM_RPC ?? "https://rpc.hyperliquid-testnet.xyz/evm";
const KEEPER_PRIVATE_KEY = process.env.KEEPER_PRIVATE_KEY ?? "";

// Asset symbol → vault address (HyperEVM testnet)
const VAULT_MAP: Record<string, string> = {
  BTC: addresses.zBTC,
  ETH: addresses.zETH,
  XRP: addresses.zXRP,
  SOL: addresses.zSOL,
};

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { signalId, asset, direction, size, price } = body as {
      signalId: string;
      asset: string;
      direction: string;
      size: number;
      price: number;
    };

    if (!signalId || !asset || !direction || typeof size !== "number" || typeof price !== "number") {
      return NextResponse.json({ error: "Invalid payload" }, { status: 400 });
    }

    // Gate: keeper private key must be configured server-side
    if (!KEEPER_PRIVATE_KEY) {
      console.error("[POST /api/signals/execute] KEEPER_PRIVATE_KEY not configured");
      return NextResponse.json({ error: "Keeper private key not configured" }, { status: 500 });
    }

    // Resolve asset symbol → vault address
    const vaultAddress = VAULT_MAP[asset.toUpperCase()] ?? asset;
    const isBuy = direction === "LONG";

    const account = privateKeyToAccount(KEEPER_PRIVATE_KEY as `0x${string}`);
    const publicClient = createPublicClient({ transport: http(RPC_URL), chain: HYPEREVM_TESTNET });
    const walletClient = createWalletClient({ account, transport: http(RPC_URL), chain: HYPEREVM_TESTNET });

    const hash = await walletClient.writeContract({
      address: addresses.StrategyExecutor,
      abi: strategyExecutorABI,
      functionName: "recordTradeManual",
      args: [vaultAddress as `0x${string}`, isBuy, BigInt(size), BigInt(Math.round(price * 1_000_000))],
    });

    const receipt = await publicClient.waitForTransactionReceipt({ hash });

    let supabase;
    try {
      supabase = await createClient();
    } catch {
      return NextResponse.json({ error: "Supabase not configured" }, { status: 503 });
    }

    await supabase
      .from("signals")
      .update({
        status: "executed",
        tx_hash: hash,
        executed_by: account.address,
        executor_address: addresses.StrategyExecutor,
      })
      .eq("id", signalId);

    await supabase.from("keeper_audit").insert({
      signal_id: signalId,
      tx_hash: hash,
      gas_used: Number(receipt.gasUsed),
      executor_address: addresses.StrategyExecutor,
      block_number: Number(receipt.blockNumber),
    });

    return NextResponse.json({ success: true, txHash: hash, blockNumber: receipt.blockNumber });
  } catch (err) {
    console.error("[POST /api/signals/execute]", err);
    return NextResponse.json({ error: "Execution failed" }, { status: 500 });
  }
}
