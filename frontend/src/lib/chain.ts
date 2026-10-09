import { defineChain, type Chain } from "viem";
import type { Address } from "viem";

// =============================================================================
// Supported networks
// =============================================================================
//
// NexEscrow is chain-agnostic. This build knows about four environments:
//
//   Nexus Testnet   3945   NEX   https://testnet.rpc.nexus.xyz
//   Nexus Mainnet   3946   NEX   https://mainnet.rpc.nexus.xyz
//   BOT Bohr        968    BOT   https://rpc.bohr.life
//   BOT Mainnet     677    BOT   https://rpc.botchain.ai
//
// SAFETY CONTRACT (do not weaken):
//   1. The build defaults to a TESTNET (BOT Bohr, 968), never to a mainnet.
//   2. A mainnet chain is only reachable when NEXT_PUBLIC_ALLOW_MAINNET=true
//      AND it is selected explicitly; otherwise the resolver falls back to
//      testnet and records a visible warning.
//   3. Every write transaction asserts connectedChainId === selectedChainId
//      and is submitted with an explicit `chainId` target; there is no
//      silent mainnet fallback anywhere.
//
// NEXT_PUBLIC_* variables must be referenced statically for Next.js to inline
// them into the client bundle — hence the explicit per-chain maps below.

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000" as Address;

function parseAddress(value: string | undefined): Address | undefined {
  if (!value) return undefined;
  const trimmed = value.trim();
  return /^0x[0-9a-fA-F]{40}$/.test(trimmed) ? (trimmed as Address) : undefined;
}

export const CHAIN_IDS = {
  nexusTestnet: 3945,
  nexusMainnet: 3946,
  botTestnet: 968,
  botMainnet: 677,
} as const;

export const TESTNET_CHAIN_IDS: readonly number[] = [3945, 968];
export const MAINNET_CHAIN_IDS: readonly number[] = [3946, 677];

export const ALLOW_MAINNET = process.env.NEXT_PUBLIC_ALLOW_MAINNET === "true";

// ---------------------------------------------------------------------------
// Chain definitions (env overrides are optional; defaults are the published
// endpoints documented in docs/DEPLOYMENT_RUNBOOK.md).
// ---------------------------------------------------------------------------

const rpcOverrides: Record<number, string | undefined> = {
  3945: process.env.NEXT_PUBLIC_RPC_URL_3945,
  3946: process.env.NEXT_PUBLIC_RPC_URL_3946,
  968: process.env.NEXT_PUBLIC_RPC_URL_968,
  677: process.env.NEXT_PUBLIC_RPC_URL_677,
};

const explorerOverrides: Record<number, string | undefined> = {
  3945: process.env.NEXT_PUBLIC_EXPLORER_URL_3945,
  3946: process.env.NEXT_PUBLIC_EXPLORER_URL_3946,
  968: process.env.NEXT_PUBLIC_EXPLORER_URL_968,
  677: process.env.NEXT_PUBLIC_EXPLORER_URL_677,
};

function httpUrl(chainId: number, fallback: string): string {
  const override = rpcOverrides[chainId]?.trim();
  return override && override.length > 0 ? override : fallback;
}

function explorerUrl(chainId: number, fallback: string): string {
  const override = explorerOverrides[chainId]?.trim();
  return override && override.length > 0 ? override : fallback;
}

export const nexusTestnet = defineChain({
  id: CHAIN_IDS.nexusTestnet,
  name: "Nexus Testnet",
  nativeCurrency: { name: "Nexus", symbol: "NEX", decimals: 18 },
  rpcUrls: { default: { http: [httpUrl(CHAIN_IDS.nexusTestnet, "https://testnet.rpc.nexus.xyz")] } },
  blockExplorers: {
    default: {
      name: "Nexus Testnet Explorer",
      url: explorerUrl(CHAIN_IDS.nexusTestnet, "https://testnet.explorer.nexus.xyz"),
    },
  },
  testnet: true,
});

export const nexusMainnet = defineChain({
  id: CHAIN_IDS.nexusMainnet,
  name: "Nexus Mainnet",
  nativeCurrency: { name: "Nexus", symbol: "NEX", decimals: 18 },
  rpcUrls: { default: { http: [httpUrl(CHAIN_IDS.nexusMainnet, "https://mainnet.rpc.nexus.xyz")] } },
  blockExplorers: {
    default: { name: "Nexus Explorer", url: explorerUrl(CHAIN_IDS.nexusMainnet, "https://explorer.nexus.xyz") },
  },
  testnet: false,
});

export const botTestnet = defineChain({
  id: CHAIN_IDS.botTestnet,
  name: "BOT Chain Bohr Testnet",
  nativeCurrency: { name: "BOT", symbol: "BOT", decimals: 18 },
  rpcUrls: { default: { http: [httpUrl(CHAIN_IDS.botTestnet, "https://rpc.bohr.life")] } },
  blockExplorers: {
    default: {
      name: "BOT Chain Bohr Explorer",
      url: explorerUrl(CHAIN_IDS.botTestnet, "https://scan.bohr.life"),
    },
  },
  testnet: true,
});

export const botMainnet = defineChain({
  id: CHAIN_IDS.botMainnet,
  name: "BOT Chain Mainnet",
  nativeCurrency: { name: "BOT", symbol: "BOT", decimals: 18 },
  rpcUrls: { default: { http: [httpUrl(CHAIN_IDS.botMainnet, "https://rpc.botchain.ai")] } },
  blockExplorers: {
    default: {
      name: "BOT Chain Explorer",
      url: explorerUrl(CHAIN_IDS.botMainnet, "https://scan.botchain.ai"),
    },
  },
  testnet: false,
});

const ALL_CHAINS: readonly Chain[] = [nexusTestnet, nexusMainnet, botTestnet, botMainnet];

export function chainById(chainId: number): Chain {
  const found = ALL_CHAINS.find((c) => c.id === chainId);
  if (!found) throw new Error(`Unsupported chain id: ${chainId}`);
  return found;
}

// ---------------------------------------------------------------------------
// Selected chain resolution — fail closed to testnet
// ---------------------------------------------------------------------------

function resolveSelectedChainId(): { chainId: number; warning?: string } {
  const requestedRaw = process.env.NEXT_PUBLIC_CHAIN_ID;
  const defaultRaw = process.env.NEXT_PUBLIC_DEFAULT_CHAIN_ID;

  const requested = requestedRaw && /^\d+$/.test(requestedRaw) ? Number(requestedRaw) : undefined;
  const configuredDefault = defaultRaw && /^\d+$/.test(defaultRaw) ? Number(defaultRaw) : undefined;
  const fallbackTestnet = CHAIN_IDS.botTestnet;

  const candidate = requested ?? configuredDefault ?? fallbackTestnet;

  if (MAINNET_CHAIN_IDS.includes(candidate)) {
    if (!ALLOW_MAINNET) {
      return {
        chainId: fallbackTestnet,
        warning:
          `Mainnet chain ${candidate} requested, but NEXT_PUBLIC_ALLOW_MAINNET is not "true". ` +
          `This build failed closed to BOT Bohr testnet (${fallbackTestnet}).`,
      };
    }
    return { chainId: candidate };
  }

  if (TESTNET_CHAIN_IDS.includes(candidate)) {
    return { chainId: candidate };
  }

  return {
    chainId: fallbackTestnet,
    warning: `Unknown chain id ${candidate}; failed closed to BOT Bohr testnet (${fallbackTestnet}).`,
  };
}

const resolution = resolveSelectedChainId();

/** The chain this build is configured to transact on. Never a mainnet by default. */
export const selectedChainId: number = resolution.chainId;
export const selectedChain: Chain = chainById(selectedChainId);

/** Non-empty when the build had to override an unsafe chain request. Show this in the UI. */
export const chainConfigWarning: string | undefined = resolution.warning;

/** Chains offered to the wallet. Mainnets only exist here when explicitly allowed. */
export const supportedChains: readonly Chain[] = ALLOW_MAINNET
  ? ALL_CHAINS
  : ALL_CHAINS.filter((c) => c.testnet === true);

export function isMainnetChain(chainId: number): boolean {
  return MAINNET_CHAIN_IDS.includes(chainId);
}

export function isTestnetChain(chainId: number): boolean {
  return TESTNET_CHAIN_IDS.includes(chainId);
}

/** "TESTNET" | "MAINNET" | "UNKNOWN" for badges. */
export function chainStatusLabel(chainId: number): "TESTNET" | "MAINNET" | "UNKNOWN" {
  if (isTestnetChain(chainId)) return "TESTNET";
  if (isMainnetChain(chainId)) return "MAINNET";
  return "UNKNOWN";
}

// ---------------------------------------------------------------------------
// Per-chain contract addresses
// ---------------------------------------------------------------------------
//
// Set NEXT_PUBLIC_ESCROW_ADDRESS_<chainId> after a deployment. There is
// deliberately no chain-agnostic "bare" address variable: a single address
// reused across chains is exactly the kind of silent cross-chain fallback this
// module exists to prevent. If the address for the selected chain is unset,
// the UI disables writes and says so.

const escrowAddressOverride: Record<number, string | undefined> = {
  3945: process.env.NEXT_PUBLIC_ESCROW_ADDRESS_3945,
  3946: process.env.NEXT_PUBLIC_ESCROW_ADDRESS_3946,
  968: process.env.NEXT_PUBLIC_ESCROW_ADDRESS_968,
  677: process.env.NEXT_PUBLIC_ESCROW_ADDRESS_677,
};

export function getEscrowAddress(chainId: number): Address {
  const parsed = parseAddress(escrowAddressOverride[chainId]);
  return parsed ?? ZERO_ADDRESS;
}

export function hasEscrowAddress(chainId: number): boolean {
  return getEscrowAddress(chainId) !== ZERO_ADDRESS;
}

/** Address for the selected chain. Hooks/components treat zero as "not deployed here". */
export const escrowAddress: Address = getEscrowAddress(selectedChainId);
export const escrowConfigured: boolean = escrowAddress !== ZERO_ADDRESS;

/** Deploy block of the configured contract, used to bound log scans. */
export function getDeployBlock(chainId: number): bigint {
  const raw =
    chainId === 3945
      ? process.env.NEXT_PUBLIC_DEPLOY_BLOCK_3945
      : chainId === 3946
        ? process.env.NEXT_PUBLIC_DEPLOY_BLOCK_3946
        : chainId === 968
          ? process.env.NEXT_PUBLIC_DEPLOY_BLOCK_968
          : chainId === 677
            ? process.env.NEXT_PUBLIC_DEPLOY_BLOCK_677
            : undefined;
  return raw && /^\d+$/.test(raw) ? BigInt(raw) : 0n;
}

// ---------------------------------------------------------------------------
// Explorer helpers
// ---------------------------------------------------------------------------

export function explorerBaseUrl(chainId: number): string {
  const chain = chainById(chainId);
  return chain.blockExplorers?.default?.url ?? "";
}

export function txExplorerUrl(chainId: number, txHash: string): string {
  const base = explorerBaseUrl(chainId);
  return base ? `${base}/tx/${txHash}` : "";
}

export function addressExplorerUrl(chainId: number, address: string): string {
  const base = explorerBaseUrl(chainId);
  return base ? `${base}/address/${address}` : "";
}

// ---------------------------------------------------------------------------
// Wrong-network guard
// ---------------------------------------------------------------------------

/** True only when the wallet is on the exact chain this build transacts on. */
export function isCorrectChain(connectedChainId: number | undefined): boolean {
  return connectedChainId === selectedChainId;
}
