import { defineChain } from "viem";

// Nexus L1 (EVM). RPC/explorer endpoints aren't hardcoded — fill them in from
// Nexus's official docs in .env.local, since testnet endpoints can change.
const rpcUrl = process.env.NEXT_PUBLIC_NEXUS_RPC_URL || "http://localhost:8545";
const explorerUrl = process.env.NEXT_PUBLIC_NEXUS_EXPLORER_URL;

export const nexusL1 = defineChain({
  id: 3946,
  name: "Nexus",
  nativeCurrency: { name: "Nexus", symbol: "NXS", decimals: 18 },
  rpcUrls: {
    default: { http: [rpcUrl] },
  },
  blockExplorers: explorerUrl
    ? { default: { name: "Nexus Explorer", url: explorerUrl } }
    : undefined,
  testnet: true,
});
