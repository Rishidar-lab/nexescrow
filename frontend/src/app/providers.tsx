"use client";

import * as React from "react";
import {
  RainbowKitProvider,
  getDefaultConfig,
  darkTheme,
} from "@rainbow-me/rainbowkit";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { WagmiProvider } from "wagmi";
import "@rainbow-me/rainbowkit/styles.css";

// Define Nexus Testnet
const nexusTestnet = {
  id: 3945,
  name: "Nexus Testnet",
  nativeCurrency: {
    decimals: 18,
    name: "Nexus",
    symbol: "NEX",
  },
  rpcUrls: {
    public: { http: ["https://testnet.explorer.nexus.xyz/api/eth-rpc"] },
    default: { http: ["https://testnet.explorer.nexus.xyz/api/eth-rpc"] },
  },
  blockExplorers: {
    default: { name: "Nexus Explorer", url: "https://testnet.explorer.nexus.xyz" },
  },
  testnet: true,
};

// Define Nexus Mainnet
const nexusMainnet = {
  id: 3946,
  name: "Nexus Mainnet",
  nativeCurrency: {
    decimals: 18,
    name: "Nexus",
    symbol: "NEX",
  },
  rpcUrls: {
    public: { http: ["https://mainnet.rpc.nexus.xyz"] },
    default: { http: ["https://mainnet.rpc.nexus.xyz"] },
  },
  blockExplorers: {
    default: { name: "Nexus Explorer", url: "https://explorer.nexus.xyz" },
  },
};

const config = getDefaultConfig({
  appName: "NexEscrow",
  projectId: "YOUR_PROJECT_ID", // Replace with real WalletConnect ID in production
  chains: [nexusTestnet, nexusMainnet],
  ssr: true, // If your dApp uses server side rendering (SSR)
});

const queryClient = new QueryClient();

export function Providers({ children }: { children: React.ReactNode }) {
  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <RainbowKitProvider theme={darkTheme()}>
          {children}
        </RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
}
