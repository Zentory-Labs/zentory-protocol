"use client";

import { ReactNode } from "react";
import { WagmiProvider, createConfig } from "wagmi";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { injected, coinbaseWallet } from "wagmi/connectors";
import { wagmiTransports, wagmiChains } from "@/lib/wallet/connectors";

const queryClient = new QueryClient();

const wagmiConfig = createConfig({
  chains: wagmiChains,
  transports: wagmiTransports,
  connectors: [
    injected({
      shimDisconnect: true,
    }),
    coinbaseWallet({
      appName: "Zentory Protocol",
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
