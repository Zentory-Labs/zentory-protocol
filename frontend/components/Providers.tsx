"use client";

import { ReactNode } from "react";
import { WagmiProvider, createConfig, http } from "wagmi";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { injected, coinbaseWallet, walletConnect } from "wagmi/connectors";
import { HYPEREVM_TESTNET } from "@/lib/contracts";

const queryClient = new QueryClient();

const RPC_URL = process.env.NEXT_PUBLIC_HYPEREVM_RPC ?? "https://rpc.hyperliquid-testnet.xyz/evm";
const WALLETCONNECT_PROJECT_ID = process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID ?? "";

const wagmiConfig = createConfig({
  chains: [HYPEREVM_TESTNET],
  transports: {
    [HYPEREVM_TESTNET.id]: http(RPC_URL),
  },
  connectors: [
    injected({
      shimDisconnect: true,
    }),
    coinbaseWallet({
      appName: "Zentory Protocol",
    }),
    ...(WALLETCONNECT_PROJECT_ID
      ? [
          walletConnect({
            projectId: WALLETCONNECT_PROJECT_ID,
          }),
        ]
      : []),
  ],
});

export default function Providers({ children }: { children: ReactNode }) {
  return (
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
    </WagmiProvider>
  );
}
