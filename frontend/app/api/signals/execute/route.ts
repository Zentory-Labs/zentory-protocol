import { NextRequest, NextResponse } from "next/server";
import { createWalletClient, http, encodeFunctionData, hexToBytes } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import type { Asset, Direction, SignalStatus } from "@/lib/signals";

const EXPLORER_BASE = "https://evm.l2scan.co/tx";

interface SignalPayload {
  id: string;
  timestamp: number;
  provider: "gp" | "lumibot" | "manual";
  asset: Asset;
  direction: Direction;
  size: number;
  price: number;
  status: SignalStatus;
  txHash?: string;
}

function encodeSignalData(
  asset: Asset,
  direction: Direction,
  size: number,
  price: number
): `0x${string}` {
  // Encode the signal execution data matching StrategyExecutor.executeSignal signature:
  // function executeSignal(bytes32 asset, int8 direction, uint256 size, uint256 price)
  // Using simple ABI encoding - adjust the selector and layout to match your contract
  const assetBytes32 = asset.padEnd(32, "\0") as `0x${string}`;
  const directionInt8 = direction === "LONG" ? 1 : direction === "SHORT" ? -1 : 0;
  const sizeHex = BigInt(Math.floor(size * 1e6)).toString(16).padStart(64, "0") as `0x${string}`;
  const priceHex = BigInt(Math.floor(price * 1e6)).toString(16).padStart(64, "0") as `0x${string}`;

  // Selector for executeSignal(bytes32, int8, uint256, uint256)
  const selector = "0xa9059cbb"; // simplified - use your actual selector
  return `${selector}${assetBytes32.slice(2)}${directionInt8.toString(16).padStart(64, "0")}${sizeHex}${priceHex}`;
}

export async function POST(req: NextRequest) {
  const rpcUrl = process.env.HYPEREVM_RPC;
  const pk = process.env.KEEPER_PRIVATE_KEY;
  const executorAddress = process.env.STRATEGY_EXECUTOR_ADDRESS as `0x${string}` | undefined;

  if (!rpcUrl || !pk || !executorAddress) {
    return NextResponse.json(
      {
        error: "Missing environment variables: HYPEREVM_RPC, KEEPER_PRIVATE_KEY, or STRATEGY_EXECUTOR_ADDRESS",
      },
      { status: 500 }
    );
  }

  try {
    const body = (await req.json()) as SignalPayload;
    const { asset, direction, size, price } = body;

    const account = privateKeyToAccount(pk as `0x${string}`);
    const walletClient = createWalletClient({
      account,
      transport: http(rpcUrl),
      chain: { id: 1, name: "HyperEVM", nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 }, rpcUrls: { default: { http: [rpcUrl] } } },
    });

    const calldata = encodeSignalData(asset, direction, size, price);

    const hash = await walletClient.sendTransaction({
      to: executorAddress,
      data: calldata as `0x${string}`,
    });

    return NextResponse.json({ txHash: hash, explorerUrl: `${EXPLORER_BASE}/${hash}` });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Execution failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
