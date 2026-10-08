import { getDefaultConfig } from "@rainbow-me/rainbowkit";
import type { Chain } from "viem";
import { supportedChains } from "./chain";

// Get a free project ID at https://cloud.reown.com (formerly WalletConnect Cloud).
// RainbowKit requires a non-empty string even to build; without a real one, the
// WalletConnect connector just won't work — injected wallets (MetaMask, etc.) are fine.
const walletConnectProjectId =
  process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID || "unset-project-id";

// Only testnets are offered unless NEXT_PUBLIC_ALLOW_MAINNET=true (see lib/chain.ts).
// The initial chain is set on RainbowKitProvider (providers.tsx) from the explicitly
// resolved selected chain; it is never mainnet unless mainnet was explicitly allowed.
export const wagmiConfig = getDefaultConfig({
  appName: "NexEscrow",
  projectId: walletConnectProjectId,
  chains: supportedChains as readonly [Chain, ...Chain[]],
  ssr: true,
});
