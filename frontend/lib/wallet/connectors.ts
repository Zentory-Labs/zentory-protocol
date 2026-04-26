/**
 * wagmi connector configuration for Zentory Protocol.
 *
 * All connector setup lives here. This module is imported by Providers.tsx
 * to build the wagmi config. Page components never import wagmi connectors directly.
 */

import { injected, coinbaseWallet } from "wagmi/connectors";
import { http } from "viem";
import { HYPEREVM_TESTNET } from "@/lib/contracts";

const RPC_URL =
  process.env.NEXT_PUBLIC_HYPEREVM_RPC ??
  "https://rpc.hyperliquid-testnet.xyz/evm";

/** wagmi transport config — single HyperEVM for now */
export const wagmiTransports = {
  [HYPEREVM_TESTNET.id]: http(RPC_URL),
} as const;

/** wagmi createConfig chains array */
export const wagmiChains = [HYPEREVM_TESTNET] as const;

/** Base connectors — injected (browser extension) + Coinbase Wallet */
export const baseConnectors = [
  injected({
    shimDisconnect: true,
  }),
  coinbaseWallet({
    appName: "Zentory Protocol",
  }),
] as const;

/**
 * Build the full wagmi connector array.
 * RainbowKit will wrap this via getDefaultConfig in Providers.tsx.
 *
 * To add WalletConnect v2: append walletConnect connector with a project ID.
 * To add Safe: append safe({ walletClientId }) from @safe-global/wagmi.
 * To add Ledger: append ledger() from @wagmi/connectors/ledger.
 *
 * The connectors array is passed to wagmi's createConfig.
 */
export function buildWagmiConnectors() {
  return [...baseConnectors];
}
