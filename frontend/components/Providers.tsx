"use client";

import { ReactNode } from "react";
import { WagmiProvider, createConfig, http } from "wagmi";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { injected, coinbaseWallet } from "wagmi/connectors";
import { HYPEREVM_TESTNET } from "@/lib/contracts";

const queryClient = new QueryClient();

const wagmiConfig = createConfig({
  chains: [HYPEREVM_TESTNET],
  transports: {
    [HYPEREVM_TESTNET.id]: http(),
  },
  connectors: [
    injected({
      shimDisconnect: true,
    }),
    coinbaseWallet({
      appName: "Zentory Protocol",
      appLogoUrl: "https://zentory.io/logo.png",
    }),
  ],
});

export default function Providers({ children }: { children: ReactNode }) {
  return (
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
    </WagmiProvider>
  );
}
