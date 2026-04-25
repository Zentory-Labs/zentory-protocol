import { NextRequest, NextResponse } from "next/server";
import { createWalletClient, http, encodeFunctionData, hexToBytes, erc20Abi } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { addresses, EXECUTOR_ABI } from "@/lib/contracts";

const EXPLORER_BASE = "https://hypurrscan.io/tx";

interface SignalPayload {
  id: string;
  asset: "BTC" | "ETH" | "XRP" | "SOL";
  direction: "LONG" | "SHORT" | "CLOSE";
  size: number;
  price: number;
  status: "pending" | "executed" | "failed";
}

// Map direction string → executor uint8
// 1=long(buy), 0=short(sell), 2=close(reduce-only)
function directionToUint8(d: string): number {
  if (d === "LONG") return 1;
  if (d === "SHORT") return 0;
  return 2; // CLOSE
}

// Asset → vault address
function assetToVault(asset: string): string {
  const map: Record<string, string> = {
    ETH: addresses.zETH,
    BTC: addresses.zBTC,
    XRP: addresses.zXRP,
    SOL: addresses.zSOL,
  };
  const vault = map[asset];
  if (!vault) throw new Error(`Unknown asset: ${asset}`);
  return vault;
}

// Size in human units → on-chain uint64
// size is a decimal like 0.1 ETH. We treat it as raw asset units with 8 decimals
// e.g. size=0.1 BTC → 10_000_000 (for 8-decimal asset)
function encodeSize(size: number, asset: string): bigint {
  const decimals = 8; // all mock assets use 8 decimals on this testnet
  return BigInt(Math.round(size * 10 ** decimals));
}

// Price in dollars → on-chain uint64 (10^8 format)
// e.g. $65,000 → 6_500_000_000
function encodePrice(price: number): bigint {
  return BigInt(Math.round(price * 1e8));
}

export async function POST(req: NextRequest) {
  const rpcUrl = process.env.NEXT_PUBLIC_HYPEREVM_RPC;
  const keeperPk = process.env.KEEPER_PRIVATE_KEY;

  if (!rpcUrl || !keeperPk) {
    return NextResponse.json(
      { error: "Missing environment variables: NEXT_PUBLIC_HYPEREVM_RPC or KEEPER_PRIVATE_KEY" },
      { status: 500 }
    );
  }

  try {
    const body = (await req.json()) as SignalPayload;
    const { asset, direction, size, price } = body;

    const vault = assetToVault(asset);
    const directionUint8 = directionToUint8(direction);
    const sizeRaw = encodeSize(size, asset);
    const priceRaw = encodePrice(price);

    const account = privateKeyToAccount(keeperPk as `0x${string}`);

    const walletClient = createWalletClient({
      account,
      transport: http(rpcUrl),
      chain: {
        id: 998,
        name: "HyperEVM Testnet",
        nativeCurrency: { name: "Hyperliquid", symbol: "HYPE", decimals: 18 },
        rpcUrls: { default: { http: [rpcUrl] } },
      },
    });

    // Encode the recordTradeManual call:
    // recordTradeManual(address vault, bool isBuy, uint64 sizeHuman, uint64 priceHuman)
    const isBuy = direction === "LONG";
    const calldata = encodeFunctionData({
      abi: EXECUTOR_ABI,
      functionName: "recordTradeManual",
      args: [vault as `0x${string}`, isBuy, sizeRaw, priceRaw],
    });

    const hash = await walletClient.sendTransaction({
      to: addresses.StrategyExecutor,
      data: calldata,
    });

    return NextResponse.json({
      txHash: hash,
      explorerUrl: `${EXPLORER_BASE}/${hash}`,
      vault,
      direction: directionUint8,
      size: sizeRaw.toString(),
      price: priceRaw.toString(),
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Execution failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
