import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/utils/supabase/server";
import { privateKeyToAccount } from "viem/accounts";
import { createPublicClient, createWalletClient, http } from "viem";
import { strategyExecutorABI, HYPEREVM_TESTNET } from "@/lib/contracts";
import { addresses } from "@/lib/contracts";

const RPC_URL = process.env.NEXT_PUBLIC_HYPEREVM_RPC ?? "https://rpc.hyperliquid-testnet.xyz/evm";
const KEEPER_PRIVATE_KEY = process.env.KEEPER_PRIVATE_KEY ?? "";

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

    if (!KEEPER_PRIVATE_KEY) {
      return NextResponse.json({ error: "Keeper private key not configured" }, { status: 500 });
    }

    const account = privateKeyToAccount(KEEPER_PRIVATE_KEY as `0x${string}`);

  const publicClient = createPublicClient({ transport: http(RPC_URL), chain: HYPEREVM_TESTNET });
  const walletClient = createWalletClient({ account, transport: http(RPC_URL), chain: HYPEREVM_TESTNET });

    const isBuy = direction === "LONG";
    const hash = await walletClient.writeContract({
      address: addresses.StrategyExecutor,
      abi: strategyExecutorABI,
      functionName: "recordTradeManual",
      args: [asset as `0x${string}`, isBuy, BigInt(size), BigInt(price * 1000000)],
    });

    const receipt = await publicClient.waitForTransactionReceipt({ hash });

    // Update signal status in Supabase
    const supabase = await createClient();
    await supabase
      .from("signals")
      .update({
        status: "executed",
        tx_hash: hash,
        executed_by: account.address,
        executor_address: addresses.StrategyExecutor,
      })
      .eq("id", signalId);

    // Log keeper audit
    await supabase.from("keeper_audit").insert({
      signal_id: signalId,
      tx_hash: hash,
      gas_used: receipt.gasUsed,
      executor_address: addresses.StrategyExecutor,
      block_number: Number(receipt.blockNumber),
    });

    return NextResponse.json({ success: true, txHash: hash, blockNumber: receipt.blockNumber });
  } catch (err) {
    console.error("[POST /api/signals/execute]", err);
    return NextResponse.json({ error: "Execution failed" }, { status: 500 });
  }
}
