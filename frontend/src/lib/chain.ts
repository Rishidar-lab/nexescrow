import { defineChain } from "viem";

// Nexus L1 mainnet. Confirmed against docs.nexus.xyz — chain ID 3946 is mainnet;
// Nexus testnet is a separate chain (ID 3945, https://testnet.rpc.nexus.xyz).
// Override via env if you want to point this build at testnet instead.
const rpcUrl = process.env.NEXT_PUBLIC_NEXUS_RPC_URL || "https://mainnet.rpc.nexus.xyz";
const explorerUrl = process.env.NEXT_PUBLIC_NEXUS_EXPLORER_URL || "https://explorer.nexus.xyz";

export const nexusL1 = defineChain({
  id: 3946,
  name: "Nexus",
  nativeCurrency: { name: "Nexus", symbol: "NEX", decimals: 18 },
  rpcUrls: {
    default: { http: [rpcUrl] },
  },
  blockExplorers: {
    default: { name: "Nexus Explorer", url: explorerUrl },
  },
  testnet: false,
});
