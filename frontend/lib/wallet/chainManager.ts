/**
 * Chain manager — handles wallet_switchEthereumChain and wallet_addEthereumChain
 * with specific error handling for codes 4902, 4001, and -32002.
 *
 * Error code meanings:
 *   4902 — Chain not added to wallet; add it first, then switch
 *   4001 — User rejected the request
 *  -32002 — Request already pending in wallet; user must check wallet
 */

import { http } from "viem";
import type { Chain } from "viem";
import type { Config } from "wagmi";

/** All chains supported by the protocol */
export const SUPPORTED_CHAINS: Record<number, Chain> = {
  998: {
    id: 998,
    name: "HyperEVM Testnet",
    nativeCurrency: { name: "Hyperliquid", symbol: "HYPE", decimals: 18 },
    rpcUrls: {
      default: { http: ["https://rpc.hyperliquid-testnet.xyz/evm"] },
      public: { http: ["https://rpc.hyperliquid-testnet.xyz/evm"] },
    },
    blockExplorers: {
      default: {
        name: "HypurrScan",
        url: "https://hypurrscan.io",
        apiUrl: "https://api.hypurrscan.io",
      },
    },
  },
  // HyperEVM Mainnet — add when deployed
  // 999: { ... },
} as const;

export const SUPPORTED_CHAIN_IDS = Object.keys(SUPPORTED_CHAINS).map(Number);

export function isChainSupported(chainId: number): boolean {
  return chainId in SUPPORTED_CHAINS;
}

/** Specific user-facing error types for chain switching */
export type ChainSwitchResult =
  | { status: "success"; chainId: number }
  | { status: "rejected" }           // code 4001
  | { status: "pending" }            // code -32002
  | { status: "not_added"; chainId: number }  // code 4902
  | { status: "unknown_error"; message: string };

/**
 * Attempt to switch to a chain. If the chain is not added (4902),
 * attempt to add it first.
 */
export async function switchToChain(
  provider: EthereumProvider,
  chainId: number
): Promise<ChainSwitchResult> {
  const chainConfig = SUPPORTED_CHAINS[chainId];
  if (!chainConfig) {
    return { status: "not_added", chainId };
  }

  const chainParam = {
    chainId: `0x${chainId.toString(16)}`,
  };

  try {
    await provider.request({
      method: "wallet_switchEthereumChain",
      params: [chainParam],
    });
    return { status: "success", chainId };
  } catch (err: any) {
    const code = err.code ?? err.status;

    if (code === 4001 || err.message?.includes("User rejected")) {
      return { status: "rejected" };
    }

    if (code === -32002) {
      return { status: "pending" };
    }

    // 4902 — chain not added; try to add it first
    if (code === 4902) {
      return { status: "not_added", chainId };
    }

    // Try adding the chain on 4902-equivalent
    if (err.message?.includes("Unrecognized chain")) {
      return { status: "not_added", chainId };
    }

    return { status: "unknown_error", message: err.shortMessage ?? err.message ?? "Unknown error" };
  }
}

/** Add a chain to the wallet */
export async function addChain(
  provider: EthereumProvider,
  chainId: number
): Promise<{ success: boolean; error?: string }> {
  const chainConfig = SUPPORTED_CHAINS[chainId];
  if (!chainConfig) {
    return { success: false, error: `Unsupported chain: ${chainId}` };
  }

  const explorerUrl = chainConfig.blockExplorers?.default?.url;

  try {
    await provider.request({
      method: "wallet_addEthereumChain",
      params: [
        {
          chainId: `0x${chainId.toString(16)}`,
          chainName: chainConfig.name,
          nativeCurrency: chainConfig.nativeCurrency,
          rpcUrls: [chainConfig.rpcUrls.default.http[0] as string],
          ...(explorerUrl ? { blockExplorerUrls: [explorerUrl] } : {}),
        },
      ],
    });
    return { success: true };
  } catch (err: any) {
    return {
      success: false,
      error: err.shortMessage ?? err.message ?? "Failed to add chain",
    };
  }
}

/**
 * Attempt switch; if chain not added, add it then retry switch.
 * Returns the final result of the switch attempt.
 */
export async function switchToChainWithAdd(
  provider: EthereumProvider,
  chainId: number
): Promise<ChainSwitchResult> {
  const result = await switchToChain(provider, chainId);

  if (result.status === "not_added") {
    const addResult = await addChain(provider, chainId);
    if (!addResult.success) {
      return { status: "unknown_error", message: addResult.error ?? "Failed to add chain" };
    }
    // Retry switch after adding
    return switchToChain(provider, chainId);
  }

  return result;
}

/** Get the current chain ID from the wallet provider */
export async function getCurrentChainId(
  provider: EthereumProvider
): Promise<number | null> {
  try {
    const chainIdHex = await provider.request({ method: "eth_chainId" });
    return parseInt(chainIdHex, 16);
  } catch {
    return null;
  }
}

/** Build a viem Transport for a given chain ID */
export function getTransportForChain(chainId: number) {
  const chain = SUPPORTED_CHAINS[chainId];
  if (!chain) {
    return http(); // fallback to public RPC
  }
  return http(chain.rpcUrls.default.http[0] as string);
}

/** EthereumProvider type — what window.ethereum exposes */
export interface EthereumProvider {
  request(args: { method: string; params?: unknown[] }): Promise<unknown>;
  on(event: string, handler: (...args: unknown[]) => void): void;
  removeListener(event: string, handler: (...args: unknown[]) => void): void;
}
