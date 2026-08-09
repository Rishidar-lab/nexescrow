import { getDefaultConfig } from "@rainbow-me/rainbowkit";
import { nexusL1 } from "./chain";

// Get a free project ID at https://cloud.reown.com (formerly WalletConnect Cloud).
// RainbowKit requires a non-empty string even to build; without a real one, the
// WalletConnect connector just won't work — injected wallets (MetaMask, etc.) are fine.
const walletConnectProjectId = process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID || "unset-project-id";

export const wagmiConfig = getDefaultConfig({
  appName: "NexEscrow",
  projectId: walletConnectProjectId,
  chains: [nexusL1],
  ssr: true,
});
